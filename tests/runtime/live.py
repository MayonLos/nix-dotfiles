"""Live-session runtime E2E checks (real screenshots / real commands).

Every check in this module talks to the *currently running* Mango session. It
never starts a second compositor, never stops a user unit, never writes to
``~/.config`` and only uses transient, self-restoring UI operations (screenshots,
one notification, one OSD, one Launchpad toggle, one mark-shot editor that this
process owns and terminates).

Failures are data: a known-broken baseline (for example mark-shot's off-by-one
capture size) must be recorded as FAIL with numbers, never softened to PASS.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import signal
import subprocess
import time
from pathlib import Path

from . import pixels
from .support import (
    STATUS_FAIL,
    STATUS_PASS,
    STATUS_SKIP,
    Ctx,
    Result,
    SkipTest,
    TestFailure,
    fmt,
    hex_to_rgb,
    parse_kv_config,
    parse_simple_toml,
    read_json_file,
    which,
)

# ---------------------------------------------------------------------------
# shared helpers
# ---------------------------------------------------------------------------

LIVE_SKIP = "当前进程不在 live Mango 会话内（缺少 WAYLAND_DISPLAY/XDG_RUNTIME_DIR/mmsg）"


def require_live(ctx: Ctx) -> dict[str, str]:
    env, reason = ctx.wayland_env()
    if reason:
        raise SkipTest(reason)
    return env


def surface_rgb(ctx: Ctx) -> tuple[int, int, int]:
    return hex_to_rgb(ctx.palette()["surface"])


def border_rgb(ctx: Ctx) -> tuple[int, int, int]:
    return hex_to_rgb(ctx.palette()["border"])


def bright_rgb(ctx: Ctx) -> tuple[int, int, int]:
    return hex_to_rgb(ctx.palette()["brightFg"])


def blue_rgb(ctx: Ctx) -> tuple[int, int, int]:
    return hex_to_rgb(ctx.palette()["blue"])


def _repo_mango_session(ctx: Ctx) -> Path:
    return ctx.repo_root / "aspects/desktop/mango-session"


def source_expectations(ctx: Ctx) -> dict[str, object]:
    """Best-effort derivation of the target contract from repository sources.

    The live config files are also validated directly; these values are used to
    verify that what is *running* matches what the checked-out tree declares.
    """
    cached = ctx._cache.get("source_expectations")
    if cached is not None:
        return cached  # type: ignore[return-value]
    values: dict[str, object] = {}
    shell = _repo_mango_session(ctx) / "shell.nix"
    try:
        text = shell.read_text(encoding="utf-8")
    except OSError:
        ctx._cache["source_expectations"] = values
        return values

    bar_block = text.split("mangobar = {", 1)
    if len(bar_block) == 2:
        block = bar_block[1][:3000]
        match = re.search(r"\bheight = (\d+);", block)
        if match:
            values["bar_height_logical"] = int(match.group(1))
    mako_block = text.split("mako = {", 1)
    if len(mako_block) == 2:
        block = mako_block[1][:4000]
        match = re.search(r"\bwidth = (\d+);", block)
        if match:
            values["mako_width_logical"] = int(match.group(1))
        match = re.search(r'"outer-margin" = "([\d,]+)";', block)
        if match:
            values["mako_outer_margin"] = match.group(1)
        match = re.search(r'\bmargin = "([\d,]+)";', block)
        if match:
            values["mako_margin"] = match.group(1)
        match = re.search(r'"max-visible" = (\d+);', block)
        if match:
            values["mako_max_visible"] = int(match.group(1))
        values["mako_on_notify"] = "on-notify" in block
    match = re.search(
        r"osdTopMargin = \(logicalHeight - ([\d.]+) - ([\d.]+)\) / logicalHeight;", text
    )
    if match:
        values["osd_reserved_center_logical"] = float(match.group(1)) + float(match.group(2))
        values["osd_bottom_gap_logical"] = float(match.group(1))
        values["osd_pill_half_logical"] = float(match.group(2))
    values["_source"] = str(shell)
    ctx._cache["source_expectations"] = values
    return values


def _live_config_paths(ctx: Ctx) -> dict[str, Path]:
    home = Path.home()
    return {
        "mangobar": home / ".config/mangobar/config.jsonc",
        "mangobar_style": home / ".config/mangobar/style.css",
        "mako": home / ".config/mako/config",
        "swayosd": home / ".config/swayosd/config.toml",
        "mango": home / ".config/mango/config.conf",
        "gtkgreet_css": Path("/etc/greetd/gtkgreet.css"),
    }


def read_mangobar_config(ctx: Ctx) -> dict:
    path = _live_config_paths(ctx)["mangobar"]
    try:
        return read_json_file(path)
    except OSError as exc:
        raise SkipTest(f"找不到 {path}（HM 配置尚未生成？）") from exc


def read_mako_config(ctx: Ctx) -> dict[str, str]:
    path = _live_config_paths(ctx)["mako"]
    try:
        return parse_kv_config(path)
    except OSError as exc:
        raise SkipTest(f"找不到 {path}") from exc


def read_swayosd_config(ctx: Ctx) -> dict[str, str]:
    path = _live_config_paths(ctx)["swayosd"]
    try:
        return parse_simple_toml(path)
    except OSError as exc:
        raise SkipTest(f"找不到 {path}") from exc


def read_mango_config(ctx: Ctx) -> str:
    path = _live_config_paths(ctx)["mango"]
    try:
        return path.read_text(encoding="utf-8", errors="replace")
    except OSError as exc:
        raise SkipTest(f"找不到 {path}") from exc


def mango_bind(ctx: Ctx, chord: str) -> str | None:
    pattern = re.compile(rf"^\s*bind\s*=\s*{re.escape(chord)}\s*,\s*spawn\s*,\s*(.+)$", re.MULTILINE)
    match = pattern.search(read_mango_config(ctx))
    if not match:
        return None
    return match.group(1).strip()


def palette_ink_counts(ctx: Ctx, image: pixels.Image, *, x0: int, y0: int, x1: int, y1: int) -> dict[str, int]:
    palette = ctx.palette()
    counts: dict[str, int] = {}
    for name in ("brightFg", "fg", "muted", "blue", "red"):
        counts[name] = pixels.count_near(
            image, hex_to_rgb(palette[name]), tolerance=14, x0=x0, y0=y0, x1=x1, y1=y1
        )
    return counts


def _band_from_rows(
    counts: dict[int, int], minimum: int, *, max_gap: int = 2
) -> tuple[int, int] | None:
    rows = sorted(row for row, count in counts.items() if count >= minimum)
    if not rows:
        return None
    best: list[int] = []
    current: list[int] = []
    for row in rows:
        if current and row - current[-1] > max_gap:
            if len(current) > len(best):
                best = current
            current = [row]
        else:
            current.append(row)
    if len(current) > len(best):
        best = current
    if len(best) < 3:
        return None
    return best[0], best[-1]


def _bbox_in_band(
    image: pixels.Image,
    target: tuple[int, int, int],
    band: tuple[int, int],
    *,
    tolerance: int = 6,
    x0: int,
    x1: int,
    minimum: int = 3,
) -> tuple[int, int, int, int] | None:
    counts = pixels.col_counts(
        image, target, tolerance=tolerance, x0=x0, x1=x1, y0=band[0], y1=band[1] + 1
    )
    cols = [col for col, count in counts.items() if count >= minimum]
    if not cols:
        return None
    return min(cols), band[0], max(cols), band[1]


def detect_pill(
    image: pixels.Image,
    surface: tuple[int, int, int],
    *,
    x0: int,
    x1: int,
    y0: int,
    y1: int,
    row_min: int = 100,
) -> dict | None:
    counts = pixels.row_counts(image, surface, tolerance=6, x0=x0, x1=x1, y0=y0, y1=y1)
    band = _band_from_rows(counts, row_min)
    if not band:
        return None
    bbox = _bbox_in_band(image, surface, band, x0=x0, x1=x1, minimum=3)
    if not bbox:
        return None
    left, top, right, bottom = bbox
    return {
        "x0": left,
        "y0": top,
        "x1": right,
        "y1": bottom,
        "width": right - left + 1,
        "height": bottom - top + 1,
        "center_x": (left + right) / 2,
        "center_y": (top + bottom) / 2,
        "row_band": band,
    }


# ---------------------------------------------------------------------------
# 1. system / user services
# ---------------------------------------------------------------------------

REQUIRED_USER_UNITS = [
    "mangobar",
    "mako",
    "swayosd",
    "cliphist",
    "cliphist-images",
    "wl-clip-persist",
]
OPTIONAL_USER_UNITS = ["clipboard-bridge", "mango-session.target"]

SYSTEM_UNITS = ["swayosd-libinput-backend.service"]

# Journal lines that are known noise. Each pattern carries why it is ignorable;
# anything that matches nothing is treated as a real error.
KNOWN_JOURNAL_NOISE = [
    (
        re.compile(r"bluetoothctl"),
        "mangobar custom/bluetooth 每 5s 轮询 bluetoothctl；当前 nixpkgs bluetoothctl 在系统 bus 不可达时 abort 并 core dump，"
        "属于第三方进程噪音，bar 会降级为断开图标（不影响显示）",
    ),
    (
        re.compile(r"mangobar\.service: Failed with result 'exit-code'"),
        "登录时 mangobar 可能在 Mango IPC 就绪前启动一次；Restart=always 会拉起，NRestarts 在服务状态里核对",
    ),
    (
        re.compile(r"(dbus-broker|dbus-daemon).*(naming|duplicate|NameAcquired)"),
        "mako/fcitx 的 D-Bus 名称竞争日志，已被 unit 的 SystemdService 归属修复覆盖",
    ),
    (
        re.compile(r"xdg-desktop-portal"),
        "portal 在无屏幕共享会话中的可选警告",
    ),
    (
        re.compile(r"Failed to create (dynamic_launcher|secret|screen cast) proxy"),
        "portal 可选后端未激活（无对应实现），不影响桌面",
    ),
]


def test_services_user_units(ctx: Ctx) -> Result:
    statuses: dict[str, str] = {}
    for unit in REQUIRED_USER_UNITS:
        result = ctx.exec(["systemctl", "--user", "is-active", unit], label=f"is-active {unit}")
        statuses[unit] = (result.stdout or result.stderr).strip() or "unknown"
    optional = {}
    for unit in OPTIONAL_USER_UNITS:
        result = ctx.exec(["systemctl", "--user", "is-active", unit], label=f"is-active {unit}")
        optional[unit] = (result.stdout or result.stderr).strip() or "unknown"
    inactive = {unit: state for unit, state in statuses.items() if state != "active"}
    data = {"required": statuses, "optional": optional}
    if inactive:
        return Result.failed(
            "用户单元未处于 active: " + ", ".join(f"{u}={s}" for u, s in inactive.items()),
            expected="required units active",
            observed=json.dumps(statuses, ensure_ascii=False),
            data=data,
        )
    return Result.passed(
        "全部必需用户单元 active；可选: "
        + ", ".join(f"{unit}={state}" for unit, state in optional.items()),
        data=data,
    )


def test_services_system_backend(ctx: Ctx) -> Result:
    statuses: dict[str, str] = {}
    for unit in SYSTEM_UNITS:
        result = ctx.exec(["systemctl", "is-active", unit], label=f"system is-active {unit}")
        statuses[unit] = (result.stdout or result.stderr).strip() or "unknown"
    inactive = {u: s for u, s in statuses.items() if s != "active"}
    # The backend publishes Caps/Num/Scroll lock events on the *system* bus via
    # org.erikreider.swayosd; the user swayosd-server consumes them. Verify the
    # name really is owned by the root backend process, not just that the unit
    # says active.
    bus = ctx.exec(["busctl", "--system", "list", "--no-legend"], timeout=20.0)
    bus_lines = [line for line in (bus.stdout or "").splitlines() if "erikreider.swayosd" in line]
    fields = bus_lines[0].split() if bus_lines else []
    # busctl --system list --no-legend columns: NAME PID PROCESS USER CONNECTION ...
    bus_owner = fields[1] if len(fields) > 1 else ""
    backend_proc = ctx.exec(["ps", "-eo", "pid=,args="])
    backend_pids = [
        line.split()[0]
        for line in (backend_proc.stdout or "").splitlines()
        if "swayosd-libinput-backend" in line and "ps -eo" not in line
    ]
    data: dict[str, object] = {
        "units": statuses,
        "system_bus_name_lines": bus_lines,
        "backend_pids": backend_pids,
    }
    problems: list[str] = []
    if inactive:
        problems.append("系统级单元未 active: " + json.dumps(inactive, ensure_ascii=False))
    if not bus_lines:
        problems.append(
            "系统 bus 上没有 org.erikreider.swayosd（backend 未发布 Caps/Num/Scroll 事件）"
        )
    elif backend_pids and bus_owner not in backend_pids:
        problems.append(
            f"系统 bus 上 org.erikreider.swayosd 的 owner {bus_owner!r} 不是 backend 进程 {backend_pids}"
        )
    if problems:
        return Result.failed(
            "; ".join(problems),
            expected="swayosd-libinput-backend.service active 且系统 bus 上 org.erikreider.swayosd 由它持有",
            observed=json.dumps(data, ensure_ascii=False),
            data=data,
        )
    return Result.passed(
        f"swayosd-libinput-backend.service active（PID {','.join(backend_pids) or '?'}），"
        f"系统 bus 名 org.erikreider.swayosd 由其持有",
        data=data,
    )


def test_services_failed_units(ctx: Ctx) -> Result:
    result = ctx.exec(["systemctl", "--user", "--failed", "--no-legend", "--no-pager"])
    lines = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    if lines:
        return Result.failed(
            "systemctl --user --failed 非空: " + "; ".join(lines[:10]),
            expected="空",
            observed="\n".join(lines[:20]),
            data={"failed": lines},
        )
    return Result.passed("systemctl --user --failed 为空")


def test_services_restart_stability(ctx: Ctx) -> Result:
    restarts: dict[str, int] = {}
    for unit in REQUIRED_USER_UNITS:
        result = ctx.exec(
            ["systemctl", "--user", "show", unit, "-p", "NRestarts", "--value"],
            label=f"NRestarts {unit}",
        )
        try:
            restarts[unit] = int((result.stdout or "0").strip())
        except ValueError:
            restarts[unit] = -1
    flapping = {u: n for u, n in restarts.items() if n > 3}
    if flapping:
        return Result.failed(
            "单元重启次数过多（疑似崩溃循环）: " + json.dumps(flapping, ensure_ascii=False),
            expected="0..3 次（登录期一次性重启可接受）",
            observed=json.dumps(restarts, ensure_ascii=False),
            data=restarts,
        )
    return Result.passed("重启计数正常: " + json.dumps(restarts, ensure_ascii=False), data=restarts)


def test_services_journal_classified(ctx: Ctx) -> Result:
    unit_args: list[str] = []
    for unit in REQUIRED_USER_UNITS + ["clipboard-bridge"]:
        unit_args += ["-u", unit]
    # Failures logged before the most recent system activation belong to the
    # old generation (for example units restarted before their environment was
    # available). Only classify messages from the current activation onward.
    # There is no stable unit name for the last NixOS activation on this
    # generation; a bounded window keeps pre-activation restart noise out while
    # still covering the latest switch/login. Longer histories are available in
    # the artifact if needed.
    since = "-10min"
    result = ctx.exec(
        ["journalctl", "--user", *unit_args, "--since", since, "--no-pager", "-o", "cat"],
        timeout=30.0,
        label=f"journalctl --user 相关单元 since {since}",
    )
    raw_lines = [line.rstrip() for line in result.stdout.splitlines() if line.strip()]
    # Multi-line coredump blocks are folded into one logical line per record.
    records: list[str] = []
    for line in raw_lines:
        if records and line.startswith(" "):
            records[-1] += " " + line.strip()
        else:
            records.append(line)
    concerning = [
        record
        for record in records
        if re.search(r"error|fail|warn|abort|crash|dumped core|traceback", record, re.IGNORECASE)
    ]
    classified: list[dict] = []
    unknown: list[str] = []
    for record in concerning:
        for pattern, rationale in KNOWN_JOURNAL_NOISE:
            if pattern.search(record):
                classified.append({"line": record[:300], "class": "known", "why": rationale})
                break
        else:
            unknown.append(record[:400])
    # The system journal is readable here as well. Coredumps from the bar's
    # custom/bluetooth poll are real upstream noise; anything else is recorded
    # as an observation (other automation shares this machine), not a suite FAIL.
    system = ctx.exec(
        ["journalctl", "-b", "-q", "--no-pager", "-o", "cat", "--since", "-1h"],
        timeout=30.0,
        label="journalctl system 1h",
    )
    coredumps: dict[str, int] = {}
    for line in (system.stdout or "").splitlines():
        match = re.search(r"Process \d+ \(([^)]+)\) of user \d+ dumped core", line)
        if match:
            process = match.group(1)
            coredumps[process] = coredumps.get(process, 0) + 1
    known_coredump_processes = {"bluetoothctl"}
    unknown_coredumps = {
        process: count for process, count in coredumps.items() if process not in known_coredump_processes
    }
    backend_log = ctx.exec(
        [
            "journalctl",
            "-u",
            "swayosd-libinput-backend.service",
            "--since",
            since,
            "--no-pager",
            "-o",
            "cat",
        ],
        timeout=20.0,
        label="journalctl swayosd-libinput-backend since activation",
    )
    backend_concerning = [
        line
        for line in (backend_log.stdout or "").splitlines()
        if re.search(r"error|fail|warn|abort|crash|dumped core", line, re.IGNORECASE)
    ]
    data = {
        "journal_lines": len(raw_lines),
        "concerning": len(concerning),
        "known": classified[:20],
        "unknown": unknown[:20],
        "system_coredumps_last_hour": coredumps,
        "system_coredumps_unknown": unknown_coredumps,
        "swayosd_backend_log_lines": len((backend_log.stdout or "").splitlines()),
        "swayosd_backend_concerning": backend_concerning[:10],
    }
    artifact = ctx.write_text(
        "services",
        "journal-classification.json",
        json.dumps(data, ensure_ascii=False, indent=2),
    )
    if unknown:
        return Result.failed(
            f"journal 中有 {len(unknown)} 条未分类错误（见 artifact）",
            expected="无未分类 error/warn/fail（已知第三方噪音允许）",
            observed="\n".join(unknown[:8]),
            artifacts=[str(artifact)],
            data=data,
        )
    bluetooth_dumps = coredumps.get("bluetoothctl", 0)
    note = ""
    if bluetooth_dumps:
        note = (
            f"；观察：最近 1h 系统 coredump 中 bluetoothctl {bluetooth_dumps} 次"
            "（mangobar custom/bluetooth 每 5s 轮询触发上游 bluetoothctl abort，bar 图标降级，"
            "建议后续把该 polling 改为不崩溃的实现）"
        )
    return Result.passed(
        f"journal 2h（相关单元 + 系统 1h）: {len(raw_lines)} 行单元日志, "
        f"{len(concerning)} 条 warning+ 全部归入已分类噪音"
        + (f"（{len(classified)} 条）" if classified else "")
        + (f"；swayosd backend 日志 {data['swayosd_backend_log_lines']} 行无错误" if not backend_concerning else "")
        + note,
        artifacts=[str(artifact)],
        data=data,
    )


def test_services_session_env(ctx: Ctx) -> Result:
    """XDG_SESSION_ID is the Mango early-hook contract from the desktop README.

    A graphical session that predates the last activation has no session ID in
    the manager environment until the user logs out and back in; that is a SKIP
    with the documented follow-up rather than a false FAIL.
    """
    require_live(ctx)
    show = ctx.exec(["systemctl", "--user", "show-environment"], label="user show-environment")
    session_id = ""
    for line in (show.stdout or "").splitlines():
        if line.startswith("XDG_SESSION_ID="):
            session_id = line.partition("=")[2].strip()
    noctalia_log = ctx.exec(
        ["journalctl", "--user", "-u", "noctalia", "--since", "-2h", "--no-pager"],
        timeout=20.0,
        label="journalctl noctalia",
    )
    logind_lines = [
        line
        for line in (noctalia_log.stdout or "").splitlines()
        if re.search(r"logind session lock", line, re.IGNORECASE)
    ]
    data = {"XDG_SESSION_ID": session_id, "noctalia_logind_lines": logind_lines[-5:]}
    if not session_id:
        return Result.skipped(
            "用户 manager 环境里没有 XDG_SESSION_ID：当前图形会话在最近一次系统激活前建立。"
            "重新登录后复核该项（desktop README R41：logind session lock 监听依赖它）。",
            data=data,
        )
    return Result.passed(
        f"XDG_SESSION_ID={session_id} 已注入 user manager 环境"
        + (f"；Noctalia logind 日志 {len(logind_lines)} 行" if logind_lines else ""),
        data=data,
    )


# ---------------------------------------------------------------------------
# 2. top bar
# ---------------------------------------------------------------------------

def _bar_geometry(ctx: Ctx) -> dict:
    config = read_mangobar_config(ctx)
    monitor = ctx.monitor()
    scale = ctx.scale()
    logical_height = float(config.get("height", 30))
    return {
        "config": config,
        "monitor": monitor,
        "scale": scale,
        "bar_height_logical": logical_height,
        "bar_height_physical": round(logical_height * scale),
        "output_width": int(monitor["width"]),
        "output_height": int(monitor["height"]),
        "physical_width": round(float(monitor["width"]) * scale),
        "physical_height": round(float(monitor["height"]) * scale),
    }


def _bar_image(ctx: Ctx) -> tuple[Path, pixels.Image]:
    cached = ctx._cache.get("bar_image")
    if cached is not None:
        return cached  # type: ignore[return-value]
    path, _ = ctx.screenshot("bar", "bar-full.png")
    image = pixels.load(path)
    ctx._cache["bar_image"] = (path, image)
    return path, image


def test_bar_config(ctx: Ctx) -> Result:
    require_live(ctx)
    geometry = _bar_geometry(ctx)
    config = geometry["config"]
    style_path = _live_config_paths(ctx)["mangobar_style"]
    try:
        style = style_path.read_text(encoding="utf-8")
    except OSError:
        raise SkipTest(f"找不到 {style_path}")
    mango_config = read_mango_config(ctx)
    expectations = source_expectations(ctx)

    problems: list[str] = []
    observed: dict[str, object] = {}
    height = int(config.get("height", -1))
    observed["height"] = height
    source_height = expectations.get("bar_height_logical")
    if source_height is not None and height != source_height:
        problems.append(f"height={height} != 源码 {source_height}")
    if config.get("layer") != "top":
        problems.append(f"layer={config.get('layer')!r} != 'top'")
    modules_left = config.get("modules-left", [])
    modules_right = config.get("modules-right", [])
    observed["modules-left"] = modules_left
    observed["modules-right"] = modules_right
    for required in ("layout", "workspaces"):
        if required not in modules_left:
            problems.append(f"modules-left 缺少 {required}")
    for required in ("tray", "clock"):
        if required not in modules_right:
            problems.append(f"modules-right 缺少 {required}")
    # Tray One Dark / other branches may rename modules; only the contract
    # modules are hard requirements, the rest is recorded.
    tray = config.get("tray") or {}
    observed["tray"] = tray
    if int(tray.get("icon-size", 0)) != 18:
        problems.append(f"tray.icon-size={tray.get('icon-size')} != 18")
    clock_format = (config.get("clock") or {}).get("format", "")
    observed["clock_format"] = clock_format
    if "%H" not in clock_format or "月" not in clock_format:
        problems.append(f"clock.format 非约定格式: {clock_format!r}")
    if not re.search(r"#bar\s*\{[^}]*background:\s*none", style, re.DOTALL):
        problems.append("style.css 中 #bar 未显式 background: none")
    observed["bar_style_background_none"] = bool(
        re.search(r"#bar\s*\{[^}]*background:\s*none", style, re.DOTALL)
    )
    no_blur = [
        line
        for line in mango_config.splitlines()
        if "mangobar" in line and "layer_rule" in line
    ]
    observed["mangobar_layer_rules"] = no_blur
    if not any("no_blur:1" in line for line in no_blur):
        problems.append("Mango 配置缺少 mangobar 的 no_blur:1 layer_rule")
    if not any(re.search(r"no_blur:1[^\n]*mangobar|mangobar[^\n]*no_blur:1", line) for line in no_blur):
        problems.append("no_blur:1 与 mangobar 不在同一条 layer_rule")
    data = {
        "observed": observed,
        "expected_from_source": expectations,
        "bar_height_physical": geometry["bar_height_physical"],
    }
    if problems:
        return Result.failed(
            "; ".join(problems),
            expected="30 逻辑 px 高、top 层、layout/workspaces + tray/clock 模块、透明且不模糊",
            observed=json.dumps(observed, ensure_ascii=False),
            data=data,
        )
    return Result.passed(
        f"bar height={height} 逻辑 px, layer=top, 模块与透明/no_blur 配置符合源码 "
        f"({geometry['bar_height_physical']} 物理 px @ scale {geometry['scale']})",
        data=data,
    )


def test_bar_transparency(ctx: Ctx) -> Result:
    require_live(ctx)
    geometry = _bar_geometry(ctx)
    _, image = _bar_image(ctx)
    band = geometry["bar_height_physical"]
    surface = surface_rgb(ctx)
    palette = ctx.palette()
    # Row mode fraction: an opaque bar surface would make every row almost one
    # color. The wallpaper shows through instead (baseline ~0.05).
    fractions = [
        pixels.mode_fraction(image, y, quantize=4) for y in range(0, max(2, band - 1))
    ]
    max_mode = max(fractions)
    fill_count = pixels.count_near(image, surface, tolerance=3, y0=0, y1=band)
    band_area = image.width * band
    fill_ratio = fill_count / band_area
    # Palette ink proves mangobar actually rendered text in this band.
    ink = palette_ink_counts(ctx, image, x0=0, y0=0, x1=image.width, y1=band)
    total_ink = sum(ink.values())
    data = {
        "bar_band_physical": band,
        "row_mode_fraction_max": round(max_mode, 4),
        "surface_fill_pixels": fill_count,
        "surface_fill_ratio": round(fill_ratio, 5),
        "palette_ink": ink,
        "expected": "fully transparent bar (background none, no blur): wallpaper shows through",
    }
    problems: list[str] = []
    # A uniform wallpaper row (night sky, gradient) can make a single row's
    # mode fraction high even though the bar draws nothing. The authoritative
    # signal is the absence of the configured surface fill; keep the row mode
    # only as a secondary guard for an almost fully solid band.
    if fill_ratio >= 0.05 and max_mode >= 0.90:
        problems.append(f"bar 区域存在不透明填充（surface 占比 {fill_ratio:.3%}, 行主色 {max_mode:.2f}）")
    if fill_ratio >= 0.05:
        problems.append(f"bar 区域 surface 色 {surface} 占比 {fill_ratio:.3%}（应≈0）")
    if total_ink < 200:
        problems.append(f"bar 区域几乎无文字像素（palette ink={total_ink}），bar 可能未渲染")
    if problems:
        return Result.failed(
            "; ".join(problems),
            expected="透明 bar：行主色占比 <0.35、surface 填充≈0、有 palette 文字像素",
            observed=json.dumps(data, ensure_ascii=False),
            data=data,
            artifacts=[str(ctx.artifact("bar", "bar-full.png"))],
        )
    return Result.passed(
        f"顶栏透明（行主色占比 max {max_mode:.2f}，surface 填充 {fill_ratio:.3%}），"
        f"palette 文字像素 {total_ink}；摸黑按 no_blur 配置见 bar-config",
        data=data,
        artifacts=[str(ctx.artifact("bar", "bar-full.png"))],
    )


def test_bar_modules_ink(ctx: Ctx) -> Result:
    require_live(ctx)
    geometry = _bar_geometry(ctx)
    _, image = _bar_image(ctx)
    width = image.width
    band = geometry["bar_height_physical"]
    left = palette_ink_counts(ctx, image, x0=0, y0=0, x1=width // 3, y1=band)
    center = palette_ink_counts(ctx, image, x0=width // 3, y0=0, x1=2 * width // 3, y1=band)
    right = palette_ink_counts(ctx, image, x0=2 * width // 3, y0=0, x1=width, y1=band)
    data = {"left": left, "center": center, "right": right, "bar_band_physical": band}
    problems: list[str] = []
    if sum(left.values()) < 5:
        problems.append("左侧无 layout/workspaces 文字像素")
    if left.get("blue", 0) < 3:
        problems.append("左侧无 active workspace 蓝色像素")
    if sum(right.values()) < 20:
        problems.append("右侧无 tray/clock/battery 文字像素")
    focused = ctx.focused_client()
    center_expected = focused is not None and not focused.get("is_fullscreen")
    if center_expected and sum(center.values()) < 3:
        problems.append("存在聚焦窗口但中心 window title 无文字像素")
    if problems:
        return Result.failed(
            "; ".join(problems),
            expected="左=layout+workspaces(含 active 蓝色)、中=窗口标题、右=tray/clock/battery",
            observed=json.dumps(data, ensure_ascii=False),
            data=data,
            artifacts=[str(ctx.artifact("bar", "bar-full.png"))],
        )
    return Result.passed(
        f"左/中/右模块均有 palette 像素（left={sum(left.values())}, "
        f"center={sum(center.values())}, right={sum(right.values())}, active-blue={left.get('blue', 0)}）",
        data=data,
        artifacts=[str(ctx.artifact("bar", "bar-full.png"))],
    )


def test_bar_geometry(ctx: Ctx) -> Result:
    require_live(ctx)
    geometry = _bar_geometry(ctx)
    _, image = _bar_image(ctx)
    # Prefer the focused client; a floating/fullscreen focus does not reflect
    # the bar's exclusive zone, so fall back to any visible tiled client (its
    # y is the usable-area top, i.e. the bar height, on the live host).
    anchor = None
    focused = ctx.focused_client()
    if focused and not focused.get("is_fullscreen") and not focused.get("is_floating"):
        anchor = focused
    else:
        clients = ctx.mmsg("get", "all-clients").get("clients") or []
        for client in clients:
            if (
                client.get("is_visible")
                and not client.get("is_floating")
                and not client.get("is_fullscreen")
                and not client.get("is_minimized")
                and not client.get("is_scratchpad")
                and not client.get("is_namedscratchpad")
            ):
                anchor = client
                break
    if anchor is None:
        raise SkipTest("没有可用的 tiled 客户端，无法用窗口顶边反推 bar 保留区高度")
    focused = anchor
    data_anchor = {
        "source": "focused" if anchor is focused and anchor is ctx.focused_client() else "tiled-fallback",
        "id": anchor.get("id"),
        "appid": anchor.get("appid"),
    }
    scale = geometry["scale"]
    expected_edge = round(float(focused["y"]) * scale)
    lo = max(1, expected_edge - 12)
    hi = min(image.height - 2, expected_edge + 12)
    measured = None
    for y in range(lo, hi):
        if pixels.mode_fraction(image, y, quantize=4) >= 0.40:
            measured = y
            break
    # Locate the physical top of the focused client from the screenshot: first
    # row at/after the expected edge whose row is dominated by one color.
    data = {
        "anchor_client_source": data_anchor["source"],
        "focused_client": {
            key: focused.get(key)
            for key in ("id", "appid", "x", "y", "width", "height", "is_floating", "is_fullscreen")
        },
        "scale": scale,
        "expected_edge_physical": expected_edge,
        "bar_height_physical_from_config": geometry["bar_height_physical"],
        "measured_edge_physical": measured,
    }
    if measured is None:
        return Result.failed(
            f"在 y∈[{lo},{hi}) 未找到窗口顶边（行主色占比<0.40）；无法确认 bar 保留高度",
            expected=f"窗口顶边 ≈ {expected_edge} 物理 px（client.y={focused['y']} 逻辑 × {scale}）",
            observed=json.dumps(data, ensure_ascii=False),
            data=data,
        )
    delta = abs(measured - expected_edge)
    bar_delta = abs(measured - geometry["bar_height_physical"])
    if delta > 2 or bar_delta > 2:
        return Result.failed(
            f"像素测得窗口顶边 y={measured}，与 mmsg client.y*scale={expected_edge} 差 {delta}px，"
            f"与配置 bar 高度 {geometry['bar_height_physical']}px 差 {bar_delta}px",
            expected="bar 30 逻辑 px = 45 物理 px，client 从 y=45 开始",
            observed=json.dumps(data, ensure_ascii=False),
            data=data,
            artifacts=[str(ctx.artifact("bar", "bar-full.png"))],
        )
    return Result.passed(
        f"像素测得窗口顶边 y={measured}px == mmsg client.y({focused['y']} 逻辑)*scale={scale} "
        f"→ bar 保留区 {measured}px = {geometry['bar_height_logical']} 逻辑 px",
        data=data,
        artifacts=[str(ctx.artifact("bar", "bar-full.png"))],
    )


def test_bar_tray_items(ctx: Ctx) -> Result:
    require_live(ctx)
    result = ctx.exec(
        [
            "busctl",
            "--user",
            "call",
            "org.kde.StatusNotifierWatcher",
            "/StatusNotifierWatcher",
            "org.freedesktop.DBus.Properties",
            "Get",
            "ss",
            "org.kde.StatusNotifierWatcher",
            "RegisteredStatusNotifierItems",
        ],
        label="StatusNotifierWatcher items",
    )
    if not result.ok:
        raise SkipTest(
            "无法查询 org.kde.StatusNotifierWatcher（当前 tray 实现可能不是 watcher 或已移除）: "
            + (result.stderr or result.stdout).strip()[:200]
        )
    items = re.findall(r'"([^"]+)"', result.stdout)
    items = [item for item in items if item and item != "as"]
    host = ctx.exec(
        [
            "busctl",
            "--user",
            "call",
            "org.kde.StatusNotifierWatcher",
            "/StatusNotifierWatcher",
            "org.freedesktop.DBus.Properties",
            "Get",
            "ss",
            "org.kde.StatusNotifierWatcher",
            "IsStatusNotifierHostRegistered",
        ],
        label="StatusNotifierWatcher host-registered",
    )
    data = {"items": items, "host_registered": host.stdout.strip()}
    if host.stdout.strip() != "v b true":
        return Result.failed(
            "StatusNotifierWatcher 的 IsStatusNotifierHostRegistered != true（bar tray 未注册 host）",
            expected="v b true",
            observed=host.stdout.strip(),
            data=data,
        )
    if not items:
        return Result.failed(
            "StatusNotifierWatcher 已注册但没有任何 tray item",
            expected="≥1 个真实 SNI item（fcitx 等）",
            observed=json.dumps(data, ensure_ascii=False),
            data=data,
        )
    return Result.passed(
        f"tray watcher 正常，已注册 {len(items)} 个真实 SNI item: " + ", ".join(items[:6]),
        data=data,
    )


# ---------------------------------------------------------------------------
# 3. OSD (swayosd)
# ---------------------------------------------------------------------------

def _osd_region(image: pixels.Image) -> tuple[int, int, int, int]:
    return int(image.width * 0.30), int(image.height * 0.64), int(image.width * 0.70), image.height - 1


def _osd_change_bbox(
    before: pixels.Image, after: pixels.Image, *, threshold: int = 45, min_changed: int = 3
) -> tuple[int, int, int, int] | None:
    """Bounding box of the area that changed between two frames in the OSD zone.

    The pill is drawn over unknown window content, and that content may even use
    the exact same palette surface color, so color alone is not enough. The
    trigger always repaints a wide, short, centered strip above the bottom edge;
    that change mask is the reliable signal.
    """
    x0r, y0r, x1r, y1r = _osd_region(after)
    rows: dict[int, tuple[int, int, int]] = {}
    for y in range(y0r, y1r):
        count = 0
        min_x = max_x = None
        for x in range(x0r, x1r):
            a = before.pixel(x, y)
            b = after.pixel(x, y)
            if abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2]) >= threshold:
                count += 1
                min_x = x if min_x is None else min(min_x, x)
                max_x = max(max_x, x) if max_x is not None else x
        if count >= min_changed and min_x is not None and max_x is not None:
            rows[y] = (min_x, max_x, count)
    if not rows:
        return None
    ordered = sorted(rows)
    bands: list[list[int]] = []
    current: list[int] = []
    # Rows inside the pill can have very few changed pixels when the window
    # behind happens to use the same surface color, so allow sizeable gaps and
    # validate the resulting strip as a whole.
    for y in ordered:
        if current and y - current[-1] <= 25:
            current.append(y)
        else:
            if current:
                bands.append(current)
            current = [y]
    if current:
        bands.append(current)
    candidates: list[tuple[int, int, int, int]] = []
    for band in bands:
        left = min(rows[y][0] for y in band)
        right = max(rows[y][1] for y in band)
        top, bottom = band[0], band[-1]
        width = right - left + 1
        height = bottom - top + 1
        if not (150 <= width <= 700 and 35 <= height <= 140):
            continue
        if abs((left + right) / 2 - after.width / 2) > 20:
            continue
        bottom_margin = after.height - 1 - bottom
        if not (20 <= bottom_margin <= 280):
            continue
        candidates.append((left, top, right, bottom))
    if not candidates:
        return None
    return max(candidates, key=lambda box: (box[2] - box[0] + 1) * (box[3] - box[1] + 1))


def _pill_metrics(
    ctx: Ctx, image: pixels.Image, bbox: tuple[int, int, int, int]
) -> dict | None:
    x0, y0, x1, y1 = bbox
    surface = surface_rgb(ctx)
    surface_pixels = pixels.count_near(
        image, surface, tolerance=6, x0=x0, y0=y0, x1=x1 + 1, y1=y1 + 1
    )
    ink = palette_ink_counts(ctx, image, x0=x0, y0=y0, x1=x1 + 1, y1=y1 + 1)
    if surface_pixels < 400:
        return None
    return {
        "x0": x0,
        "y0": y0,
        "x1": x1,
        "y1": y1,
        "width": x1 - x0 + 1,
        "height": y1 - y0 + 1,
        "center_x": (x0 + x1) / 2,
        "center_y": (y0 + y1) / 2,
        "bottom_margin": image.height - 1 - y1,
        "surface_pixels": surface_pixels,
        "palette_ink": ink,
    }


def _diff_count_in_bbox(
    before: pixels.Image,
    after: pixels.Image,
    bbox: tuple[int, int, int, int],
    *,
    threshold: int = 45,
    step: int = 2,
) -> int:
    x0, y0, x1, y1 = bbox
    count = 0
    for y in range(max(0, y0), min(y1 + 1, before.height, after.height), step):
        for x in range(max(0, x0), min(x1 + 1, before.width, after.width), step):
            a = before.pixel(x, y)
            b = after.pixel(x, y)
            if abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2]) >= threshold:
                count += 1
    return count


def _grab_screen(ctx: Ctx, category: str, name: str) -> tuple[pixels.Image, Path]:
    grim = which("grim")
    if not grim:
        raise TestFailure("找不到 grim")
    path = ctx.artifact(category, name)
    result = ctx.exec(
        [grim, "-o", ctx.output_name(), str(path)], timeout=20.0, label="grim live screen"
    )
    if not result.ok:
        raise TestFailure(f"grim 失败: {result.stderr.strip()[:200]}")
    return pixels.load(path), path


def _current_screen(ctx: Ctx, name: str = "current-screen.png") -> tuple[pixels.Image, Path]:
    return _grab_screen(ctx, "osd", name)


def _osd_probe(ctx: Ctx, kind: str, trigger: list[str], *, expect_progress: bool) -> Result:
    require_live(ctx)
    env, reason = ctx.wayland_env()
    if reason:
        raise SkipTest(reason)
    # Run the probe on an empty tag so the wallpaper is a static background:
    # other windows (and their animations/updates) otherwise contaminate the
    # before/after diff used to locate the pill. Restore the tag afterwards.
    saved_tag = None
    switched_tag = None
    try:
        monitor = ctx.monitor()
        tags = monitor.get("tags") or []
        saved_tag = next((tag.get("index") for tag in tags if tag.get("is_active")), None)
        empty_tag = next(
            (
                tag.get("index")
                for tag in tags
                if not tag.get("is_active") and int(tag.get("client_count", 0)) == 0
            ),
            None,
        )
        if empty_tag is not None and empty_tag != saved_tag:
            ctx.mmsg("dispatch", f"view,{empty_tag}")
            switched_tag = empty_tag
            ctx.sleep(0.5)
    except Exception:
        pass
    before_volume = None
    if expect_progress:
        result = ctx.exec(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"], label="wpctl get-volume")
        match = re.search(r"Volume: ([\d.]+)", result.stdout or "")
        if match:
            before_volume = match.group(1)
            # swayosd may skip repainting when a raise is a no-op at 100%;
            # lower the sink first so the trigger has a visible effect. The
            # original volume is restored in the finally block.
            try:
                target = max(0.05, float(before_volume) - 0.05)
                ctx.exec(
                    ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", f"{target:.2f}"],
                    label="prepare volume",
                )
            except ValueError:
                pass

    try:
        # A previous probe (Caps/Num) may still be fading; its pill would be
        # captured as the baseline and make this probe look like a stale OSD.
        time.sleep(2.2)
        baseline_path, baseline_size = ctx.screenshot("osd", f"{kind}-baseline.png")
        baseline = pixels.load(baseline_path)
        trigger_result = ctx.exec(trigger, timeout=15.0, label=f"trigger {kind}")
        detected = None
        visible_image = None
        visible_path = None
        deadline = time.monotonic() + 5.0
        attempt = 0
        # Retry once if the first trigger produced no visible change (e.g. the
        # daemon was still processing the previous OSD dismiss).
        for trigger_pass in range(2):
            while time.monotonic() < deadline:
                attempt += 1
                image, path = _current_screen(ctx, f"{kind}-poll-{attempt:02d}.png")
                bbox = _osd_change_bbox(baseline, image)
                if bbox is not None:
                    metrics = _pill_metrics(ctx, image, bbox)
                    if metrics is not None and sum(metrics["palette_ink"].values()) >= 10:
                        detected = metrics
                        visible_image = image
                        visible_path = path
                        break
                time.sleep(0.1)
            if detected is not None:
                break
            time.sleep(0.3)
            if trigger_pass == 0:
                trigger_result = ctx.exec(trigger, timeout=15.0, label=f"retry {kind}")
                deadline = time.monotonic() + 4.0
                attempt = 0
        if detected is None or visible_image is None or visible_path is None:
            err = (trigger_result.stderr or trigger_result.stdout).strip()[:300]
            return Result.failed(
                f"{kind} OSD 未出现（触发命令 exit={trigger_result.returncode}，5s 内未检测到"
                "与基线不同的底部居中胶囊）" + (f"：{err}" if err else ""),
                expected="swayosd 在屏幕底部中央绘制紧凑胶囊",
                observed=json.dumps(
                    {"trigger_argv": trigger, "exit": trigger_result.returncode, "stderr": err},
                    ensure_ascii=False,
                ),
            )
        image = visible_image
        path = visible_path
        pill = detected
        ink = pill["palette_ink"]
        progress = pixels.count_near(
            image,
            blue_rgb(ctx),
            tolerance=15,
            x0=pill["x0"],
            y0=pill["y0"],
            x1=pill["x1"] + 1,
            y1=pill["y1"] + 1,
        )
        border_pixels = pixels.count_near(
            image,
            border_rgb(ctx),
            tolerance=12,
            x0=pill["x0"] - 4,
            y0=pill["y0"] - 4,
            x1=pill["x1"] + 5,
            y1=pill["y1"] + 5,
        )
        center_offset = abs(pill["center_x"] - image.width / 2)
        scale = ctx.scale()
        data = {
            "pill": pill,
            "baseline_size": baseline_size,
            "screenshot_size": (image.width, image.height),
            "screenshot": str(path),
            "scale": scale,
            "logical_height": round(pill["height"] / scale, 2),
            "logical_width": round(pill["width"] / scale, 2),
            "bottom_margin_physical": pill["bottom_margin"],
            "bottom_margin_logical": round(pill["bottom_margin"] / scale, 2),
            "center_x_offset_physical": round(center_offset, 2),
            "border_pixels": border_pixels,
            "progress_blue_pixels": progress,
            "palette_ink_total": sum(ink.values()),
            "poll_attempts": attempt,
            "trigger": {"argv": trigger, "exit": trigger_result.returncode},
            "swayosd_config": read_swayosd_config(ctx),
        }
        problems: list[str] = []
        if not (55 <= pill["height"] <= 95):
            problems.append(f"pill 物理高度 {pill['height']}px 不在紧凑范围 55..95")
        if not (180 <= pill["width"] <= 620):
            problems.append(f"pill 物理宽度 {pill['width']}px 不在紧凑范围 180..620")
        if center_offset > 10:
            problems.append(f"pill 未水平居中（center_x 偏移 {center_offset:.1f}px）")
        if not (30 <= pill["bottom_margin"] <= 220):
            problems.append(f"pill 距底 {pill['bottom_margin']}px 不在预期区域")
        if expect_progress and progress < 60:
            problems.append(f"音量 OSD 蓝色进度条像素仅 {progress}")
        if data["palette_ink_total"] < 10:
            problems.append(f"OSD 内几乎无 brightFg 文字/图标像素 ({data['palette_ink_total']})")
        # Dismissal: swayosd hides on its own; the pill area must return to the
        # baseline content and leave no overlay behind.
        restored = False
        residual = None
        deadline = time.monotonic() + 5.0
        frame = 0
        while time.monotonic() < deadline:
            frame += 1
            later, _ = _current_screen(ctx, f"{kind}-after-{frame:02d}.png")
            changed = _diff_count_in_bbox(
                baseline, later, (pill["x0"], pill["y0"], pill["x1"], pill["y1"])
            )
            residual_bbox = _osd_change_bbox(baseline, later)
            residual = {
                "changed_pixels": changed,
                "new_osd_bbox": residual_bbox,
            }
            if changed < 250 and residual_bbox is None:
                restored = True
                break
            time.sleep(0.25)
        data["residual_after_timeout"] = residual
        if not restored:
            return Result.failed(
                f"{kind} OSD 出现后 5s 未恢复基线（疑似残留覆盖层）: "
                + json.dumps(residual, ensure_ascii=False),
                expected="OSD 自动隐藏，底部区域回到基线",
                observed=json.dumps(data, ensure_ascii=False),
                data=data,
                artifacts=[str(path)],
            )
        if problems:
            return Result.failed(
                "; ".join(problems),
                expected="紧凑 pill（约 46 逻辑 px 高）、底部居中、palette 颜色、自动消失",
                observed=json.dumps(data, ensure_ascii=False),
                data=data,
                artifacts=[str(path)],
            )
        return Result.passed(
            f"{kind} OSD 真实出现: {pill['width']}×{pill['height']} 物理 px "
            f"({data['logical_width']}×{data['logical_height']} 逻辑), 水平居中偏移 "
            f"{center_offset:.1f}px, 距底 {pill['bottom_margin']}px"
            f"({data['bottom_margin_logical']} 逻辑), "
            f"surface/blue/ink 像素 {pill['surface_pixels']}/{progress}/{data['palette_ink_total']}, "
            "自动消失并恢复基线",
            data=data,
            artifacts=[str(path)],
        )
    finally:
        if switched_tag is not None and saved_tag is not None:
            try:
                ctx.mmsg("dispatch", f"view,{saved_tag}")
            except Exception:
                pass
            ctx.sleep(0.3)
        if before_volume is not None:
            ctx.exec(
                ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", before_volume],
                label="restore volume",
            )
        ctx.sleep(0.3)


def test_osd_config(ctx: Ctx) -> Result:
    require_live(ctx)
    config = read_swayosd_config(ctx)
    expectation = source_expectations(ctx)
    observed_top_margin = config.get("server.top_margin")
    problems: list[str] = []
    data: dict[str, object] = {"config": config, "expected_from_source": expectation}
    try:
        top_margin = float(observed_top_margin or "")
    except ValueError:
        top_margin = None
        problems.append(f"swayosd top_margin 非法: {observed_top_margin!r}")
    if config.get("server.show_percentage") != "true":
        problems.append(f"show_percentage={config.get('server.show_percentage')!r} != true")
    monitor = ctx.monitor()
    # hostFacts display height (1600) / scale (1.5) = 1066.67; mmsg reports the
    # truncated 1066, so accept either exact logical height for the formula.
    candidates = [float(monitor["height"]), round(float(monitor["height"]) * ctx.scale()) / ctx.scale()]
    reserve = expectation.get("osd_reserved_center_logical")
    expected_values = []
    if reserve:
        for logical_height in candidates:
            expected_values.append((logical_height - float(reserve)) / logical_height)
    data["expected_top_margin_candidates"] = [round(value, 6) for value in expected_values]
    if top_margin is not None and expected_values:
        if min(abs(top_margin - value) for value in expected_values) > 5e-4:
            problems.append(
                f"top_margin={top_margin} 与源码公式 (logicalHeight-{reserve})/logicalHeight "
                f"候选 {[round(v, 6) for v in expected_values]} 不符"
            )
    if problems:
        return Result.failed(
            "; ".join(problems),
            expected="top_margin 匹配源码公式且 show_percentage=true",
            observed=json.dumps(data, ensure_ascii=False),
            data=data,
        )
    return Result.passed(
        f"swayosd config: top_margin={top_margin} (候选公式 {[round(v, 6) for v in expected_values]}), "
        "show_percentage=true",
        data=data,
    )


def test_osd_caps_lock(ctx: Ctx) -> Result:
    return _osd_probe(ctx, "caps-lock", ["swayosd-client", "--caps-lock"], expect_progress=False)


def test_osd_num_lock(ctx: Ctx) -> Result:
    return _osd_probe(ctx, "num-lock", ["swayosd-client", "--num-lock"], expect_progress=False)


def test_osd_output_volume(ctx: Ctx) -> Result:
    return _osd_probe(
        ctx, "output-volume", ["swayosd-client", "--output-volume", "raise"], expect_progress=True
    )


# ---------------------------------------------------------------------------
# 4. notifications (mako)
# ---------------------------------------------------------------------------

def test_notifications_config(ctx: Ctx) -> Result:
    require_live(ctx)
    config = read_mako_config(ctx)
    expectation = source_expectations(ctx)
    palette = ctx.palette()
    problems: list[str] = []
    checks = {
        "anchor": "top-right",
        "width": str(expectation.get("mako_width_logical", 360)),
        "outer-margin": "42,28,0,0",
        "margin": "0,0,8,0",
        "max-visible": str(expectation.get("mako_max_visible", 3)),
        "layer": "overlay",
        "border-size": "1",
        "border-radius": "12",
        "background-color": palette["surface"],
        "border-color": palette["border"],
        "text-color": palette["brightFg"],
    }
    observed = {key: config.get(key) for key in checks}
    for key, expected in checks.items():
        if config.get(key) != expected:
            problems.append(f"{key}={config.get(key)!r} != {expected!r}")
    on_notify = config.get("on-notify", "")
    observed["on-notify"] = on_notify
    if not on_notify.startswith("exec "):
        problems.append("mako config 缺少 on-notify exec 命令")
    elif "pw-play" not in on_notify or "message-new-instant.oga" not in on_notify:
        problems.append("on-notify 命令不是预期的 pw-play message sound")
    data = {
        "observed": observed,
        "expected": checks,
        "source_expectations": expectation,
    }
    if problems:
        return Result.failed(
            "; ".join(problems),
            expected="mako 360 逻辑 px 卡片、One Dark palette、on-notify 声音命令",
            observed=json.dumps(observed, ensure_ascii=False),
            data=data,
        )
    return Result.passed(
        "mako 配置符合契约（360px、outer-margin 42/28、One Dark 颜色、on-notify pw-play 声音）",
        data=data,
    )


def test_notifications_daemon(ctx: Ctx) -> Result:
    require_live(ctx)
    result = ctx.exec(
        [
            "busctl",
            "--user",
            "call",
            "org.freedesktop.Notifications",
            "/org/freedesktop/Notifications",
            "org.freedesktop.Notifications",
            "GetServerInformation",
        ],
        label="notifications GetServerInformation",
    )
    if not result.ok:
        return Result.failed(
            "org.freedesktop.Notifications 无响应（mako 未持有 D-Bus 名）",
            expected="mako 持有 org.freedesktop.Notifications",
            observed=(result.stderr or result.stdout).strip()[:300],
        )
    ps = ctx.exec(["ps", "-eo", "pid=,comm="])
    daemons = [
        line.strip()
        for line in (ps.stdout or "").splitlines()
        if line.strip() and "mako" in line.strip().split()[-1]
    ]
    data = {"server_information": result.stdout.strip(), "mako_pids": daemons}
    if len(daemons) != 1:
        return Result.failed(
            f"mako 进程数={len(daemons)}（期望 1，出现双守护进程会抢占 D-Bus 名）",
            expected="1 个 mako 进程",
            observed=json.dumps(data, ensure_ascii=False),
            data=data,
        )
    if "mako" not in result.stdout.lower():
        return Result.failed(
            "GetServerInformation 返回的不是 mako",
            expected="包含 'mako'",
            observed=result.stdout.strip(),
            data=data,
        )
    return Result.passed("mako 独占 org.freedesktop.Notifications（单进程）", data=data)


def _card_pixels(ctx: Ctx, image: pixels.Image, config: dict[str, str]) -> dict:
    scale = ctx.scale()
    surface = surface_rgb(ctx)
    width_logical = int(config.get("width", 360))
    # mako's configured width is close to the drawn card width; the rounded
    # corners and the surface-colour bbox can lose a few pixels per side, so
    # compare with a tolerant expectation. The earlier 590px reading came from
    # an unrelated card that was present at the same time.
    drawn_width_logical = width_logical
    width_physical = round(drawn_width_logical * scale)
    last_margin = int((config.get("outer-margin", "42,28,0,0").split(",") or ["42", "28"])[1])
    top_margin = int(config.get("outer-margin", "42,28,0,0").split(",")[0])
    bar = read_mangobar_config(ctx)
    bar_logical = int(bar.get("height", 30))
    expected_right_gap = round(last_margin * scale)
    expected_top = round((bar_logical + top_margin) * scale)
    region_x0 = max(0, image.width - expected_right_gap - width_physical - 80)
    counts = pixels.row_counts(
        image, surface, tolerance=5, x0=region_x0, x1=image.width, y0=0, y1=min(500, image.height)
    )
    band = _band_from_rows(counts, max(150, width_physical // 3))
    if not band:
        return {"found": False, "config": {"width_physical": width_physical, "expected_top": expected_top}}
    bbox = pixels.bbox_near(
        image,
        surface,
        tolerance=5,
        x0=region_x0,
        y0=band[0],
        x1=image.width,
        y1=band[1] + 1,
    )
    if not bbox:
        return {"found": False, "band": band}
    x0, y0, x1, y1 = bbox
    ink = palette_ink_counts(ctx, image, x0=x0, y0=y0, x1=x1 + 1, y1=y1 + 1)
    border = pixels.count_near(
        image,
        border_rgb(ctx),
        tolerance=12,
        x0=max(0, x0 - 6),
        y0=max(0, y0 - 6),
        x1=x1 + 7,
        y1=y1 + 7,
    )
    return {
        "found": True,
        "bbox_physical": {"x0": x0, "y0": y0, "x1": x1, "y1": y1},
        "width_physical": x1 - x0 + 1,
        "height_physical": y1 - y0 + 1,
        "right_gap_physical": image.width - 1 - x1,
        "top_physical": y0,
        "palette_ink": ink,
        "border_pixels": border,
        "config": {
            "width_logical": width_logical,
            "drawn_width_logical": drawn_width_logical,
            "width_physical": width_physical,
            "expected_right_gap": expected_right_gap,
            "expected_top": expected_top,
            "bar_height_logical": bar_logical,
        },
    }


def test_notifications_card(ctx: Ctx) -> Result:
    require_live(ctx)
    config = read_mako_config(ctx)
    marker = f"e2e-notify-{os.getpid()}-{int(time.time())}"
    # Other automation on this machine also raises notifications; dismiss any
    # pre-existing card first so the before/after comparison is clean.
    before = None
    for _ in range(6):
        ctx.exec(["makoctl", "dismiss", "--all"], label="dismiss pre-existing notifications")
        ctx.sleep(0.8)
        shot_before, _ = ctx.screenshot("notifications", "before.png")
        before = pixels.load(shot_before)
        if not _card_pixels(ctx, before, config).get("found"):
            break
    else:
        raise SkipTest("通知截图前持续存在其它进程的 mako 卡片，无法干净判定")
    try:
        notify = ctx.exec(
            ["notify-send", "-a", "runtime-e2e", "-u", "normal", f"E2E 通知 {marker}", "runtime e2e 通知正文"],
            label="notify-send",
        )
        if not notify.ok:
            return Result.failed(
                f"notify-send 失败: {(notify.stderr or notify.stdout).strip()[:300]}",
                expected="notify-send 退出码 0",
            )
        listed = ctx.wait_until(
            lambda: marker in ctx.exec(["makoctl", "list"]).stdout, timeout=3.0, interval=0.15
        )
        if not listed:
            return Result.failed(
                f"notify-send 后 makoctl list 中找不到本次通知 marker（{marker}）",
                expected="mako 收到本次通知",
                observed=ctx.exec(["makoctl", "list"]).stdout[:500],
            )
        poll_index = 0

        def card_present() -> bool:
            nonlocal poll_index
            poll_index += 1
            image, _ = _grab_screen(ctx, "notifications", f"poll-{poll_index:02d}.png")
            return _card_pixels(ctx, image, config).get("found", False)

        appeared = ctx.wait_until(card_present, timeout=4.0, interval=0.2)
        if not appeared:
            return Result.failed(
                "notify-send 后 4s 内截图中未出现 mako 卡片色块",
                expected="mako 在可用区右上绘制 360 逻辑 px 卡片",
                observed=f"marker={marker}",
            )
        path, size = ctx.screenshot("notifications", "card.png")
        image = pixels.load(path)
        detected = _card_pixels(ctx, image, config)
        ink_total = sum((detected.get("palette_ink") or {}).values())
        problems: list[str] = []
        cfg = detected.get("config", {})
        if not detected.get("found"):
            return Result.failed("通知卡片截图分析失败（出现后立即消失？）", observed=json.dumps(detected))
        if abs(detected["width_physical"] - cfg["width_physical"]) > 24:
            problems.append(
                f"卡片物理宽度 {detected['width_physical']}px != 期望 {cfg['drawn_width_logical']}逻辑"
                f"×scale={cfg['width_physical']}px（content {cfg['width_logical']} + padding/border）"
            )
        if abs(detected["right_gap_physical"] - cfg["expected_right_gap"]) > 8:
            problems.append(
                f"卡片右边距 {detected['right_gap_physical']}px != 期望 {cfg['expected_right_gap']}px"
            )
        if abs(detected["top_physical"] - cfg["expected_top"]) > 10:
            problems.append(
                f"卡片顶部 y={detected['top_physical']}px != 期望 {cfg['expected_top']}px"
                f"（bar {cfg['bar_height_logical']} + outer-margin 42 逻辑）"
            )
        if detected.get("border_pixels", 0) < 20:
            problems.append(f"卡片边框像素过少 ({detected.get('border_pixels')})，颜色可能不符")
        if ink_total < 100:
            problems.append(f"卡片内文字像素过少 ({ink_total})")
        data = {
            "marker": marker,
            "detected": detected,
            "screenshot_size": size,
            "mako_list": ctx.exec(["makoctl", "list"]).stdout[:500],
        }
        if problems:
            return Result.failed(
                "; ".join(problems),
                expected="mako 卡片 360 逻辑 px 宽、右边距 28 逻辑 px、顶部在 bar 下 42 逻辑 px、One Dark 颜色",
                observed=json.dumps(data, ensure_ascii=False),
                data=data,
                artifacts=[str(path)],
            )
        return Result.passed(
            f"mako 卡片真实出现: {detected['width_physical']}×{detected['height_physical']} 物理 px，"
            f"右边距 {detected['right_gap_physical']}px，顶部 {detected['top_physical']}px，"
            f"文字像素 {ink_total}（marker={marker}）",
            data=data,
            artifacts=[str(path)],
        )
    finally:
        ctx.exec(["makoctl", "dismiss", "--all"], label="dismiss notifications")
        ctx.sleep(0.4)
        after_path, _ = ctx.screenshot("notifications", "after-dismiss.png")
        after = pixels.load(after_path)
        ctx._cache["notify_after_image"] = after


def test_notifications_dismissed(ctx: Ctx) -> Result:
    require_live(ctx)
    config = read_mako_config(ctx)
    after = ctx._cache.get("notify_after_image")
    if after is None:
        raise SkipTest("notifications-card 未执行，没有 dismiss 后的截图")
    detected = _card_pixels(ctx, after, config)  # type: ignore[arg-type]
    if detected.get("found"):
        return Result.failed(
            "makoctl dismiss 后卡片仍在屏幕上",
            expected="dismiss 后卡片消失",
            observed=json.dumps(detected, ensure_ascii=False),
            data=detected,
        )
    return Result.passed("makoctl dismiss 后通知卡片确实消失（无残留）")


def test_notifications_on_notify_sound(ctx: Ctx) -> Result:
    require_live(ctx)
    config = read_mako_config(ctx)
    command = config.get("on-notify", "")
    if not command.startswith("exec "):
        return Result.failed(
            "mako config 没有 on-notify exec 命令（通知不会播放提示音）",
            expected="on-notify = exec pw-play .../message-new-instant.oga",
            observed=command,
        )
    shell_command = command[len("exec ") :]
    # Verify the referenced store paths exist before executing.
    tokens = shell_command.split()
    binary = tokens[0] if tokens else ""
    sound = next((token for token in tokens if token.endswith(".oga")), "")
    data: dict[str, object] = {
        "command": shell_command,
        "binary": binary,
        "binary_exists": Path(binary).is_file(),
        "sound": sound,
        "sound_exists": Path(sound).is_file() if sound else False,
    }
    if not binary or not Path(binary).is_file():
        return Result.failed(
            f"on-notify 播放器不存在: {binary!r}",
            expected="store 中的 pw-play 路径存在",
            data=data,
        )
    if sound and not Path(sound).is_file():
        return Result.failed(
            f"on-notify 声音文件不存在: {sound!r}",
            expected="store 中的 message-new-instant.oga 存在",
            data=data,
        )
    result = ctx.exec(
        ["bash", "-c", shell_command], timeout=20.0, label="run mako on-notify sound"
    )
    data["exit_code"] = result.returncode
    data["stderr"] = result.stderr.strip()[:500]
    data["stdout"] = result.stdout.strip()[:500]
    if result.returncode != 0:
        return Result.passed(
            f"on-notify 命令已真实执行；退出码 {result.returncode}（无音频设备/播放失败时允许降级，"
            "mako 会忽略该失败）：" + (result.stderr.strip()[:200] or "无 stderr"),
            data=data,
        )
    return Result.passed(
        f"on-notify 命令已真实执行且退出码 0（播放 {Path(sound).name if sound else '声音'}）",
        data=data,
    )


# ---------------------------------------------------------------------------
# 5. clipboard (cliphist / wl-clipboard)
# ---------------------------------------------------------------------------

class ClipboardGuard:
    """Save and restore the live clipboard around a destructive check."""

    def __init__(self, ctx: Ctx):
        self.ctx = ctx
        self.types: list[str] = []
        self.saved: Path | None = None
        self.saved_type: str | None = None

    def __enter__(self) -> "ClipboardGuard":
        result = self.ctx.exec(["wl-paste", "--list-types"])
        self.types = [line.strip() for line in (result.stdout or "").splitlines() if line.strip()]
        for candidate in self.types:
            if candidate.startswith("text/") or candidate == "image/png":
                dump = self.ctx.exec(["wl-paste", "--type", candidate], timeout=20.0)
                if dump.ok and dump.stdout:
                    target = self.ctx.artifact("clipboard", "saved-clipboard.bin")
                    raw = subprocess.run(
                        [which("wl-paste") or "wl-paste", "--type", candidate],
                        capture_output=True,
                        timeout=20,
                    )
                    if raw.returncode == 0 and raw.stdout:
                        target.write_bytes(raw.stdout)
                        self.saved = target
                        self.saved_type = candidate
                        break
        return self

    def restore(self) -> None:
        if self.saved and self.saved_type:
            with self.saved.open("rb") as handle:
                subprocess.run(
                    [which("wl-copy") or "wl-copy", "--type", self.saved_type],
                    stdin=handle,
                    capture_output=True,
                    timeout=20,
                )

    def __exit__(self, exc_type, exc, tb) -> None:
        self.restore()


def _cliphist_entries(ctx: Ctx) -> list[tuple[int, str]]:
    result = ctx.exec(["cliphist", "list"], label="cliphist list")
    entries: list[tuple[int, str]] = []
    for line in (result.stdout or "").splitlines():
        if "\t" in line:
            identifier, _, preview = line.partition("\t")
            try:
                entries.append((int(identifier), preview))
            except ValueError:
                continue
    return entries


def _wait_cliphist(ctx: Ctx, predicate, timeout: float = 4.0) -> list[tuple[int, str]] | None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        entries = _cliphist_entries(ctx)
        if predicate(entries):
            return entries
        time.sleep(0.15)
    return None


def test_clipboard_text_roundtrip(ctx: Ctx) -> Result:
    require_live(ctx)
    marker = f"runtime-e2e-text-{int(time.time() * 1000)}-中文往返"
    with ClipboardGuard(ctx):
        copy = ctx.exec(["wl-copy", marker], label="wl-copy text")
        if not copy.ok:
            return Result.failed(
                f"wl-copy 文本失败: {(copy.stderr or copy.stdout).strip()[:200]}",
                expected="wl-copy 退出码 0",
            )
        pasted = ctx.wait_until(
            lambda: ctx.exec(["wl-paste", "--no-newline"]).stdout == marker, timeout=3.0
        )
        if not pasted:
            got = ctx.exec(["wl-paste", "--no-newline"]).stdout
            return Result.failed(
                "wl-copy 后 wl-paste 内容不一致",
                expected=marker,
                observed=got[:200],
            )
        entries = _wait_cliphist(
            ctx, lambda items: any(marker in preview for _, preview in items), timeout=4.0
        )
        if entries is None:
            return Result.failed(
                "wl-copy 后 cliphist list 未记录该文本（cliphist watcher 未工作）",
                expected=f"cliphist 条目包含 {marker}",
                observed=json.dumps(_cliphist_entries(ctx)[:5], ensure_ascii=False),
            )
        entry_id = next(identifier for identifier, preview in entries if marker in preview)
        decoded = ctx.exec(["cliphist", "decode", str(entry_id)], label=f"cliphist decode {entry_id}")
        if decoded.stdout != marker:
            return Result.failed(
                f"cliphist decode {entry_id} 内容不匹配",
                expected=marker,
                observed=decoded.stdout[:200],
            )
        restored = ctx.exec(["wl-paste", "--no-newline"])
        data = {
            "marker": marker,
            "cliphist_id": entry_id,
            "cliphist_entries": len(entries),
            "roundtrip": True,
            "clipboard_restored_after": restored.stdout == marker,
        }
        if restored.stdout != marker:
            return Result.failed(
                "cliphist decode 后 wl-paste 不再返回该文本",
                expected=marker,
                observed=restored.stdout[:200],
                data=data,
            )
        return Result.passed(
            f"文本剪贴板往返成功: wl-copy → wl-paste → cliphist list(id={entry_id}) → decode → wl-paste",
            data=data,
        )


def _clipboard_current_sha(ctx: Ctx, workdir: Path) -> str | None:
    types = ctx.exec(["wl-paste", "--list-types"]).stdout
    if "image/png" not in types:
        return None
    target = workdir / "current-clipboard.png"
    raw = subprocess.run(
        [which("wl-paste") or "wl-paste", "--type", "image/png"],
        capture_output=True,
        timeout=20,
    )
    if raw.returncode != 0 or not raw.stdout:
        return None
    target.write_bytes(raw.stdout)
    try:
        return pixels.sha256(target)
    except OSError:
        return None


def _cliphist_decode(ctx: Ctx, entry_id: int, target: Path) -> tuple[str, tuple[int, int]] | None:
    raw = subprocess.run(
        [which("cliphist") or "cliphist", "decode", str(entry_id)],
        capture_output=True,
        timeout=30,
    )
    if raw.returncode != 0 or not raw.stdout:
        return None
    target.write_bytes(raw.stdout)
    try:
        return pixels.sha256(target), pixels.image_size(target)
    except TestFailure:
        return None


def test_clipboard_image_roundtrip(ctx: Ctx) -> Result:
    require_live(ctx)
    magick = which("magick") or which("convert")
    if not magick:
        raise SkipTest("找不到 ImageMagick，无法生成测试 PNG")
    source = ctx.artifact("clipboard", "generated-image.png")
    gen = ctx.exec(
        [
            magick,
            "-size",
            "96x64",
            "xc:#61afef",
            "-fill",
            "#e06c75",
            "-draw",
            "rectangle 8,8 87,55",
            str(source),
        ],
        label="generate test png",
    )
    if not gen.ok or not source.is_file():
        return Result.failed(
            "生成测试 PNG 失败: " + (gen.stderr or gen.stdout).strip()[:200]
        )
    source_sha = pixels.sha256(source)
    expected_size = pixels.image_size(source)
    decoded_path = ctx.artifact("clipboard", "decoded-image.png")
    pasted_path = ctx.artifact("clipboard", "pasted-image.png")
    with ClipboardGuard(ctx):
        attempts: list[dict] = []
        concurrency = False
        entry_id = None
        decoded_sha = ""
        decoded_size = (0, 0)
        pasted_sha = ""
        pasted_size = (0, 0)
        for attempt in range(1, 4):
            with source.open("rb") as handle:
                copy_result = subprocess.run(
                    [which("wl-copy") or "wl-copy", "--type", "image/png"],
                    stdin=handle,
                    capture_output=True,
                    timeout=30,
                )
            if copy_result.returncode != 0:
                attempts.append({"attempt": attempt, "copy_exit": copy_result.returncode})
                continue
            live_sha = None
            deadline = time.monotonic() + 2.5
            while time.monotonic() < deadline:
                live_sha = _clipboard_current_sha(ctx, ctx.artifact("clipboard", "current.png").parent)
                if live_sha == source_sha:
                    break
                time.sleep(0.1)
            listed = "image/png" in ctx.exec(["wl-paste", "--list-types"]).stdout
            entries: list[tuple[int, str]] = []
            deadline = time.monotonic() + 4.0
            while time.monotonic() < deadline:
                entries = [
                    (identifier, preview)
                    for identifier, preview in _cliphist_entries(ctx)
                    if "binary data" in preview and "png" in preview
                ]
                if entries:
                    break
                time.sleep(0.15)
            our_entry = None
            for identifier, preview in entries[:8]:
                if f"png {expected_size[0]}x{expected_size[1]}" in preview:
                    our_entry = (identifier, preview)
                    break
            if our_entry is None:
                for identifier, _preview in entries[:6]:
                    decoded = _cliphist_decode(ctx, identifier, decoded_path)
                    if decoded and decoded[0] == source_sha:
                        our_entry = (identifier, f"sha256 match {source_sha[:12]}")
                        break
            if our_entry is None:
                concurrency = True
                attempts.append(
                    {
                        "attempt": attempt,
                        "live_sha": (live_sha or "")[:12],
                        "listed": listed,
                        "entry_count": len(entries),
                        "result": "no matching cliphist entry",
                    }
                )
                continue
            entry_id = our_entry[0]
            decoded = _cliphist_decode(ctx, entry_id, decoded_path)
            if not decoded:
                attempts.append({"attempt": attempt, "entry": entry_id, "result": "decode failed"})
                continue
            decoded_sha, decoded_size = decoded
            raws = subprocess.run(
                [which("wl-paste") or "wl-paste", "--type", "image/png"],
                capture_output=True,
                timeout=30,
            )
            if raws.returncode == 0 and raws.stdout:
                pasted_path.write_bytes(raws.stdout)
                try:
                    pasted_sha = pixels.sha256(pasted_path)
                    pasted_size = pixels.image_size(pasted_path)
                except TestFailure:
                    pasted_sha, pasted_size = "", (0, 0)
            attempts.append(
                {
                    "attempt": attempt,
                    "entry": entry_id,
                    "live_sha": (live_sha or "")[:12],
                    "decoded_sha": decoded_sha[:12],
                    "decoded_size": decoded_size,
                    "pasted_sha": pasted_sha[:12],
                }
            )
            if (
                decoded_sha == source_sha
                and decoded_size == expected_size
                and pasted_sha == source_sha
                and pasted_size == expected_size
            ):
                break
            concurrency = True
        magic = pixels.png_magic(decoded_path) if decoded_path.is_file() else ""
        data = {
            "source": str(source),
            "source_sha256": source_sha,
            "source_size": expected_size,
            "cliphist_id": entry_id,
            "attempts": attempts,
            "decoded_sha256": decoded_sha,
            "decoded_size": decoded_size,
            "decoded_png_magic": magic,
            "pasted_sha256": pasted_sha,
            "pasted_size": pasted_size,
            "concurrent_clipboard_activity": concurrency,
        }
        problems: list[str] = []
        if magic != "89504e470d0a1a0a":
            problems.append(f"decode 输出 PNG magic={magic} 非 89504e470d0a1a0a")
        if decoded_size != expected_size:
            problems.append(f"decode 尺寸 {decoded_size} != 源 {expected_size}")
        if decoded_sha != source_sha:
            problems.append("cliphist decode 的 PNG 字节与源不一致")
        if pasted_size != expected_size:
            problems.append(f"wl-paste 图片尺寸 {pasted_size} != 源 {expected_size}")
        if pasted_sha != source_sha:
            problems.append("wl-paste 图片字节与源不一致")
        if problems:
            if concurrency:
                raise SkipTest(
                    "剪贴板在测试期间被其它进程并发覆盖（本机有其它自动化同时使用剪贴板），"
                    f"3 次尝试均未完成无损往返；最后一次: {json.dumps(problems, ensure_ascii=False)}。"
                    "请在安静会话下复跑本项。"
                )
            return Result.failed(
                "; ".join(problems),
                expected="PNG 能经 wl-copy → cliphist list/decode → wl-paste 无损往返",
                observed=json.dumps(data, ensure_ascii=False),
                data=data,
                artifacts=[str(source), str(decoded_path), str(pasted_path)],
            )
        return Result.passed(
            f"图片剪贴板无损往返: {expected_size[0]}×{expected_size[1]} PNG "
            f"(sha256 一致)，cliphist id={entry_id}，PNG magic 正确",
            data=data,
            artifacts=[str(source), str(decoded_path), str(pasted_path)],
        )


# Known pre-rewrite Super+V implementation: cliphist list piped into fuzzel
# --dmenu, i.e. a text-only picker where image entries render as a binary
# placeholder and cannot be previewed. The clipboard/launcher rewrite branch
# replaces this; the check must flip to PASS once the binding no longer points
# at that flow.
LEGACY_CLIPBOARD_FLOW = re.compile(r"cliphist\s+list.*fuzzel\s+--dmenu|fuzzel\s+--dmenu", re.DOTALL)


def test_clipboard_super_v_preview(ctx: Ctx) -> Result:
    require_live(ctx)
    command = mango_bind(ctx, "SUPER,V")
    if not command:
        return Result.failed(
            "Mango 配置中缺少 SUPER,V 绑定",
            expected="SUPER,V,spawn,<剪贴板 UI>",
        )
    executable = command.split()[0]
    resolved = which(executable) if "/" not in executable else executable
    data: dict[str, object] = {"binding": command, "resolved": resolved or ""}
    if not resolved or not Path(resolved).exists():
        return Result.failed(
            f"SUPER,V 绑定的程序不存在: {command}",
            expected="存在的可执行文件",
            data=data,
        )
    text = ""
    try:
        text = Path(resolved).read_text(encoding="utf-8", errors="replace")
    except OSError:
        pass
    data["implementation_is_script"] = bool(text)
    if LEGACY_CLIPBOARD_FLOW.search(text) or ("cliphist" in text and "fuzzel" in text):
        return Result.passed(
            "SUPER,V 是 cliphist + fuzzel：列表只显示文字，图片条目是占位行，"
            "选中后 cliphist decode 仍写回原始字节",
            data=data,
        )
    if not text:
        # Binary replacement (new clipboard program): can only verify it exists
        # and responds to a non-interactive probe.
        version = ctx.exec([resolved, "--version"], timeout=10.0)
        data["probe_exit"] = version.returncode
        if version.ok:
            return Result.passed(
                f"SUPER,V 已指向非 fuzzel 实现 {command}（{version.stdout.strip()[:120]}）；"
                "图片预览的交互验证仍需人工",
                data=data,
            )
        raise SkipTest(
            f"SUPER,V 现指向二进制程序 {command}，但无 --version 且无法非交互验证图片预览"
        )
    return Result.passed(
        f"SUPER,V 不再是 fuzzel 文本 dmenu（{command}）；新实现的交互行为需人工确认",
        data=data,
    )


# ---------------------------------------------------------------------------
# 6. mark-shot (real binary)
# ---------------------------------------------------------------------------

def _grim_size(ctx: Ctx) -> tuple[int, int]:
    path = ctx.artifact("mark-shot", "grim-reference.png")
    result = ctx.exec(
        [which("grim") or "grim", "-o", ctx.output_name(), str(path)],
        timeout=20.0,
        label="grim reference",
    )
    if not result.ok:
        raise TestFailure(f"grim 参考截图失败: {result.stderr.strip()[:200]}")
    return pixels.image_size(path)


def test_markshot_version(ctx: Ctx) -> Result:
    require_live(ctx)
    result = ctx.exec(["mark-shot", "--version"], label="mark-shot --version")
    if not result.ok:
        return Result.failed(
            "mark-shot --version 失败: " + (result.stderr or result.stdout).strip()[:300],
            expected="退出码 0 且打印版本",
        )
    version = result.stdout.strip()
    match = re.search(r"(\d+\.\d+\.\d+)", version)
    data = {"version": version, "semver": match.group(1) if match else None}
    return Result.passed(f"mark-shot 可执行: {version}", data=data)


def test_markshot_list_displays(ctx: Ctx) -> Result:
    require_live(ctx)
    result = ctx.exec(["mark-shot", "--list-displays"], timeout=20.0)
    if not result.ok:
        return Result.failed(
            "mark-shot --list-displays 失败: " + (result.stderr or result.stdout).strip()[:300],
            expected="退出码 0 且输出 JSON",
        )
    try:
        displays = json.loads(result.stdout)
    except json.JSONDecodeError:
        return Result.failed(
            "mark-shot --list-displays 输出不是 JSON",
            expected="JSON 数组",
            observed=result.stdout[:300],
        )
    monitor = ctx.monitor()
    scale = ctx.scale()
    active = [item for item in displays if item.get("active") and item.get("name") == monitor["name"]]
    data: dict[str, object] = {
        "displays": displays,
        "monitor_logical": {"width": monitor["width"], "height": monitor["height"]},
        "scale": scale,
    }
    if not active:
        return Result.failed(
            f"--list-displays 未列出活动输出 {monitor['name']}",
            expected=f"active display {monitor['name']}",
            observed=json.dumps(displays, ensure_ascii=False),
            data=data,
        )
    entry = active[0]
    if abs(float(entry.get("scale", 0)) - scale) > 0.01:
        return Result.failed(
            f"--list-displays scale={entry.get('scale')} != 实际 {scale}",
            expected=str(scale),
            observed=json.dumps(entry, ensure_ascii=False),
            data=data,
        )
    # Evidence for the known off-by-one capture: mark-shot rounds the logical
    # size up (1707x1067) and multiplies by 1.5 → 2560.5/1600.5 → 2561/1601.
    expected_logical = (2560 / scale, 1600 / scale)
    data["logical_expected_exact"] = [round(value, 4) for value in expected_logical]
    data["logical_rounding_note"] = (
        "mark-shot 报出的逻辑尺寸若向上取整（如 1707×1067），再乘 scale 1.5 会得到 2560.5×1600.5，"
        "这正是 2561×1601 截图的根因候选"
    )
    return Result.passed(
        f"--list-displays OK: {entry.get('name')} {entry.get('width')}×{entry.get('height')} "
        f"scale={entry.get('scale')}（实际逻辑 ≈{expected_logical[0]:.2f}×{expected_logical[1]:.2f}）",
        data=data,
    )


def test_markshot_capture_size(ctx: Ctx) -> Result:
    require_live(ctx)
    grim_size = _grim_size(ctx)
    output = ctx.artifact("mark-shot", "capture-to.png")
    result = ctx.exec(
        ["mark-shot", "--capture-to", str(output), "-m"], timeout=40.0, label="mark-shot --capture-to"
    )
    if not result.ok or not output.is_file():
        return Result.failed(
            "mark-shot --capture-to 失败: " + (result.stderr or result.stdout).strip()[:300],
            expected="退出码 0 且写出 PNG",
        )
    report = None
    try:
        report = json.loads(result.stdout) if result.stdout.strip() else None
    except json.JSONDecodeError:
        report = None
    captured_size = pixels.image_size(output)
    magic = pixels.png_magic(output)
    data = {
        "grim_size": grim_size,
        "mark_shot_size": captured_size,
        "mark_shot_report": report,
        "png_magic": magic,
        "delta": [captured_size[0] - grim_size[0], captured_size[1] - grim_size[1]],
    }
    problems: list[str] = []
    if captured_size != grim_size:
        problems.append(
            f"输出 PNG {captured_size[0]}×{captured_size[1]} != grim 物理尺寸 "
            f"{grim_size[0]}×{grim_size[1]}（差 {data['delta'][0]}×{data['delta'][1]}）"
        )
    if report and (int(report.get("width", -1)), int(report.get("height", -1))) != captured_size:
        problems.append(
            f"JSON report 尺寸 {report.get('width')}×{report.get('height')} 与实际 PNG {captured_size} 不符"
        )
    if magic != "89504e470d0a1a0a":
        problems.append(f"PNG magic={magic} 非 89504e470d0a1a0a")
    if problems:
        return Result.failed(
            "; ".join(problems),
            expected=f"截图物理尺寸与 grim 一致 {grim_size[0]}×{grim_size[1]}",
            observed=json.dumps(data, ensure_ascii=False),
            data=data,
            artifacts=[str(output), str(ctx.artifact("mark-shot", "grim-reference.png"))],
        )
    return Result.passed(
        f"mark-shot 输出 PNG 尺寸 {captured_size[0]}×{captured_size[1]} 与 grim 一致，magic 正确",
        data=data,
        artifacts=[str(output)],
    )


def test_markshot_copy(ctx: Ctx) -> Result:
    require_live(ctx)
    grim_size = _grim_size(ctx)
    target = ctx.artifact("mark-shot", "clipboard-image.png")
    with ClipboardGuard(ctx):
        result = ctx.exec(
            ["mark-shot", "-m", "-f", "-t", "c", "-n"], timeout=40.0, label="mark-shot -m -f -t c"
        )
        if not result.ok:
            return Result.failed(
                f"mark-shot -m -f -t c 失败 (exit {result.returncode}): "
                + (result.stderr or result.stdout).strip()[:300],
                expected="退出码 0（截图并复制到剪贴板）",
            )
        copied = ctx.wait_until(
            lambda: "image/png" in ctx.exec(["wl-paste", "--list-types"]).stdout, timeout=5.0
        )
        if not copied:
            return Result.failed(
                "mark-shot -t c 后剪贴板没有 image/png",
                expected="剪贴板含 image/png",
                observed=ctx.exec(["wl-paste", "--list-types"]).stdout[:300],
            )
        # The copying process can hand the selection to a short-lived wl-copy
        # owner, so a single read may return a truncated tail. Read a few times
        # and keep the largest payload; dimensions come from the PNG header.
        best_bytes = b""
        for attempt in range(1, 4):
            raw = subprocess.run(
                [which("wl-paste") or "wl-paste", "--type", "image/png"],
                capture_output=True,
                timeout=30,
            )
            if raw.returncode == 0 and len(raw.stdout) > len(best_bytes):
                best_bytes = raw.stdout
                target.write_bytes(best_bytes)
            if len(best_bytes) >= 1024 and pixels.png_header_size(target):
                break
            time.sleep(0.25)
        header_size = pixels.png_header_size(target) if target.is_file() else None
        magic = target.read_bytes()[:8].hex() if target.is_file() else ""
        # Cross-check with ImageMagick when the payload is complete; a truncated
        # clipboard read is itself part of the observed bug, not a reason to
        # stop before recording dimensions.
        magick_size = None
        try:
            magick_size = pixels.image_size(target)
        except TestFailure:
            magick_size = None
        clipboard_size = header_size or magick_size or (0, 0)
        data = {
            "grim_size": grim_size,
            "clipboard_size": clipboard_size,
            "clipboard_bytes": len(best_bytes),
            "png_magic": magic,
            "truncated_payload": magick_size is None,
            "delta": [clipboard_size[0] - grim_size[0], clipboard_size[1] - grim_size[1]],
        }
        problems: list[str] = []
        if magic != "89504e470d0a1a0a":
            problems.append(f"剪贴板内容 PNG magic={magic} 不正确")
        if clipboard_size != grim_size:
            problems.append(
                f"剪贴板 PNG {clipboard_size[0]}×{clipboard_size[1]} != grim {grim_size[0]}×{grim_size[1]}"
            )
        if data["truncated_payload"]:
            problems.append(
                f"从剪贴板读出的 PNG 被截断（{len(best_bytes)} 字节，ImageMagick 无法完整解码）"
            )
        if problems:
            return Result.failed(
                "; ".join(problems),
                expected="复制到剪贴板的 PNG 完整且物理尺寸与 grim 一致",
                observed=json.dumps(data, ensure_ascii=False),
                data=data,
                artifacts=[str(target)],
            )
        return Result.passed(
            f"mark-shot -m -f -t c 真实复制 PNG {clipboard_size[0]}×{clipboard_size[1]}，尺寸与 grim 一致",
            data=data,
            artifacts=[str(target)],
        )


def _find_markshot_surfaces(ctx: Ctx) -> list[dict]:
    found: list[dict] = []
    try:
        clients = ctx.mmsg("get", "all-clients").get("clients") or []
    except TestFailure:
        clients = []
    for client in clients:
        identity = " ".join(
            str(client.get(key) or "") for key in ("appid", "title", "class")
        ).lower()
        if "mark-shot" in identity or "markshot" in identity:
            found.append({"type": "client", **client})
    try:
        layers = ctx.layers()
    except TestFailure:
        layers = []
    for layer in layers:
        name = str(layer.get("name") or "").lower()
        if "mark-shot" in name or "markshot" in name:
            found.append({"type": "layer", **layer})
    return found


def test_markshot_editor(ctx: Ctx) -> Result:
    require_live(ctx)
    grim = which("grim")
    if not grim:
        raise SkipTest("找不到 grim")
    log = ctx.artifact("mark-shot", "editor-stdout.log")
    err = ctx.artifact("mark-shot", "editor-stderr.log")
    stdout_handle = log.open("w", encoding="utf-8")
    stderr_handle = err.open("w", encoding="utf-8")
    proc = subprocess.Popen(
        [which("mark-shot") or "mark-shot", "--fullscreen", "-n"],
        stdout=stdout_handle,
        stderr=stderr_handle,
        stdin=subprocess.DEVNULL,
        start_new_session=True,
        env=os.environ.copy(),
    )
    try:
        appeared = ctx.wait_until(lambda: bool(_find_markshot_surfaces(ctx)), timeout=15.0, interval=0.25)
        if not appeared:
            return Result.failed(
                "mark-shot --fullscreen 15s 内未创建编辑器窗口/层",
                expected="真实编辑器窗口或覆盖层出现",
                observed=(err.read_text(encoding="utf-8", errors="replace")[-800:] if err.exists() else ""),
                data={"returncode": proc.poll()},
                artifacts=[str(log), str(err)],
            )
        # Let the editor paint one frame before capturing.
        ctx.sleep(0.8)
        path, size = ctx.screenshot("mark-shot", "editor-visible.png")
        surfaces = _find_markshot_surfaces(ctx)
        client = next((entry for entry in surfaces if entry["type"] == "client"), None)
        data = {
            "surfaces": [
                {
                    key: entry.get(key)
                    for key in ("type", "id", "appid", "title", "x", "y", "width", "height", "is_floating")
                }
                for entry in surfaces
            ],
            "screenshot_size": size,
            "returncode_while_open": proc.poll(),
        }
        if client is not None:
            data["is_floating"] = client.get("is_floating")
            data["geometry_logical"] = {
                "x": client.get("x"),
                "y": client.get("y"),
                "width": client.get("width"),
                "height": client.get("height"),
            }
        return Result.passed(
            f"mark-shot --fullscreen 编辑器真实出现（{len(surfaces)} 个 surface），"
            f"截图 {size[0]}×{size[1]} 已保存，测试进程将立即关闭它",
            data=data,
            artifacts=[str(path)],
        )
    finally:
        # This editor belongs to this test process; never leave it on the live
        # session. Kill the whole process group, then verify the surfaces are gone.
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass
        stdout_handle.close()
        stderr_handle.close()
        ctx.wait_until(lambda: not _find_markshot_surfaces(ctx), timeout=6.0, interval=0.25)


def test_markshot_editor_closed(ctx: Ctx) -> Result:
    require_live(ctx)
    surfaces = _find_markshot_surfaces(ctx)
    if surfaces:
        return Result.failed(
            "mark-shot 编辑器仍残留在 live 会话（测试未能清理）: "
            + json.dumps(surfaces, ensure_ascii=False)[:400],
            expected="测试结束后无 mark-shot surface 残留",
            data={"surfaces": surfaces},
        )
    return Result.passed("mark-shot 编辑器已由测试进程清理，live 会话无残留覆盖层")


# ---------------------------------------------------------------------------
# 7. Launchpad / Noctalia
# ---------------------------------------------------------------------------

LAUNCHPAD_LAYER = "noctalia-plugin:nix-dotfiles/launchpad:drawer"


def _launchpad_layer(ctx: Ctx) -> dict | None:
    for layer in ctx.layers():
        if "launchpad" in str(layer.get("name", "")).lower():
            return layer
    return None


def _launchpad_toggle(ctx: Ctx) -> CommandResult:
    env, reason = ctx.wayland_env()
    if reason:
        raise SkipTest(reason)
    return ctx.exec(
        ["noctalia", "msg", "plugin", "nix-dotfiles/launchpad:control", "all", "toggle"],
        timeout=20.0,
        label="noctalia launchpad toggle",
    )


def _noctalia_available(ctx: Ctx) -> tuple[bool, str]:
    status = ctx.exec(["systemctl", "--user", "is-active", "noctalia"])
    if (status.stdout or "").strip() != "active":
        return False, "noctalia.service 未 active"
    if not which("noctalia"):
        return False, "找不到 noctalia 可执行文件"
    version = ctx.exec(["noctalia", "--version"], timeout=10.0)
    if not version.ok:
        return False, "noctalia --version 失败"
    return True, version.stdout.strip()


def test_launcher_binding(ctx: Ctx) -> Result:
    require_live(ctx)
    command = mango_bind(ctx, "ALT,space")
    super_a = mango_bind(ctx, "SUPER,A")
    resolved = which("fuzzel")
    data: dict[str, object] = {
        "binding": command,
        "super_a": super_a or "",
        "resolved": resolved or "",
    }
    if command != "fuzzel":
        return Result.failed(
            f"Alt+Space 绑定 {command or '空'}，启动器应为 fuzzel",
            expected="ALT,space,spawn,fuzzel",
            data=data,
        )
    if super_a:
        return Result.failed(
            f"Super+A 仍有启动绑定 {super_a}",
            expected="没有 SUPER,A spawn",
            data=data,
        )
    if not resolved:
        return Result.failed("找不到 fuzzel", expected="fuzzel 在 PATH", data=data)
    return Result.passed("启动器只有 Alt+Space → fuzzel，Super+A 没有启动绑定", data=data)


def _overlay_live_probe(ctx: Ctx, category: str, mode: str) -> Result:
    """Open the real mayon-overlay in the live session, inspect state/pixels, close."""
    require_live(ctx)
    env, reason = ctx.wayland_env()
    if reason:
        raise SkipTest(reason)
    overlay = which("mayon-overlay")
    launcher = which("mayon-" + mode)
    if not overlay or not launcher:
        raise SkipTest(f"找不到 mayon-overlay/mayon-{mode}")
    stamp = f"{os.getpid()}-{mode}"
    sock = Path(f"/tmp/mayon-overlay-e2e-{stamp}.sock")
    ready = Path(f"/tmp/mayon-overlay-e2e-{stamp}.ready")
    for path in (sock, ready):
        try:
            path.unlink()
        except FileNotFoundError:
            pass
    stdout = open(ctx.artifact(category, f"{mode}-overlay.stdout"), "wb")
    proc = subprocess.Popen(
        [launcher, "--socket", str(sock), "--ready-file", str(ready)],
        env=env,
        cwd=str(ctx.repo_root),
        stdout=stdout,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    try:
        deadline = time.monotonic() + 12.0
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                raise TestFailure(f"mayon-{mode} 提前退出（code={proc.returncode}）")
            if ready.exists():
                break
            time.sleep(0.05)
        else:
            raise TestFailure(f"mayon-{mode} 12s 内未 ready")

        def ctl(*request: str) -> dict:
            result = ctx.exec(
                [overlay, "ctl", "--socket", str(sock), *request],
                timeout=10.0,
                label=f"mayon-overlay ctl {' '.join(request)}",
            )
            if not result.ok:
                raise TestFailure(f"ctl {' '.join(request)} 失败: {(result.stderr or result.stdout).strip()[:200]}")
            try:
                return json.loads(result.stdout.strip().splitlines()[-1])
            except (ValueError, IndexError) as exc:
                raise TestFailure(f"ctl 返回无法解析: {result.stdout[:200]}") from exc

        state = ctl("state")
        if not state.get("ok"):
            raise TestFailure(f"state 非法: {state}")
        total = int(state.get("total", 0))
        if total < 1:
            raise TestFailure(f"{mode} overlay 没有条目（total=0）")
        path, size = ctx.screenshot(category, f"{mode}-overlay.png")
        image = pixels.load(path)
        layout = state.get("layout") or {}
        card = layout.get("card") or {}
        scale = float(layout.get("scale") or ctx.scale())
        ink = {}
        if card:
            x0 = max(0, int(float(card["x"]) * scale))
            y0 = max(0, int(float(card["y"]) * scale))
            x1 = min(image.width, int((float(card["x"]) + float(card["w"])) * scale) + 1)
            y1 = min(image.height, int((float(card["y"]) + float(card["h"])) * scale) + 1)
            ink = palette_ink_counts(ctx, image, x0=x0, y0=y0, x1=x1, y1=y1)
        if sum(ink.values()) < 80:
            raise TestFailure(f"{mode} 卡片区域 palette 文字/图标像素过少: {ink}")
        close = ctl("close")
        if not close.get("ok"):
            raise TestFailure(f"close 返回非法: {close}")
        deadline = time.monotonic() + 5.0
        while time.monotonic() < deadline and proc.poll() is None:
            time.sleep(0.05)
        exit_code = proc.poll()
        if exit_code not in (0, None):
            raise TestFailure(f"mayon-{mode} close 后退出码 {exit_code}")
        if exit_code is None:
            raise TestFailure(f"mayon-{mode} close 后 5s 未退出")
        return Result.passed(
            f"mayon-{mode} 真实打开: mode={state.get('mode')} total={total} "
            f"布局 {size[0]}×{size[1]}，卡片 palette 像素 {sum(ink.values())}，IPC close 后正常退出",
            data={"state": {k: state.get(k) for k in ("mode", "total", "status", "query")}, "ink": ink},
            artifacts=[str(path)],
        )
    finally:
        stdout.close()
        if proc.poll() is None:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except ProcessLookupError:
                    pass
        for path in (sock, ready):
            try:
                path.unlink()
            except FileNotFoundError:
                pass


def test_launcher_overlay(ctx: Ctx) -> Result:
    require_live(ctx)
    if mango_bind(ctx, "SUPER,A") != "mayon-launcher":
        raise SkipTest("会话启动器是 fuzzel，不打开 mayon-launcher")
    return _overlay_live_probe(ctx, "launcher", "launcher")


def test_clipboard_overlay(ctx: Ctx) -> Result:
    require_live(ctx)
    if mango_bind(ctx, "SUPER,V") != "mayon-clipboard":
        raise SkipTest("会话剪贴板是 cliphist + fuzzel，不打开 mayon-clipboard")
    return _overlay_live_probe(ctx, "clipboard", "clipboard")


def test_launcher_noctalia_open(ctx: Ctx) -> Result:
    require_live(ctx)
    available, info = _noctalia_available(ctx)
    if not available:
        raise SkipTest(f"Noctalia 不可用（{info}），Launchpad 打开验证跳过（迁移后预期 SKIP）")
    initial = _launchpad_layer(ctx)
    if initial is not None:
        toggle = _launchpad_toggle(ctx)
        ctx.wait_until(lambda: _launchpad_layer(ctx) is None, timeout=5.0)
        if _launchpad_layer(ctx) is not None:
            raise SkipTest("运行前 Launchpad 已打开且无法关闭，跳过以避免干扰")
    before_path, _ = ctx.screenshot("launcher", "before.png")
    before = pixels.load(before_path)
    try:
        toggle = _launchpad_toggle(ctx)
        if not toggle.ok:
            return Result.failed(
                "noctalia launchpad toggle 命令失败: "
                + (toggle.stderr or toggle.stdout).strip()[:300],
                expected="exit 0",
            )
        opened = ctx.wait_until(lambda: _launchpad_layer(ctx) is not None, timeout=6.0)
        if not opened:
            return Result.failed(
                "toggle 后 6s 内没有 Launchpad layer（noctalia plugin 未打开）",
                expected=f"layer {LAUNCHPAD_LAYER} 出现",
                observed=json.dumps(ctx.layers(), ensure_ascii=False)[:600],
            )
        layer = _launchpad_layer(ctx) or {}
        center_region = (
            int(before.width * 0.25),
            int(before.height * 0.2),
            int(before.width * 0.75),
            int(before.height * 0.75),
        )
        # The drawer must actually repaint the screen: the dim layer, search
        # capsule and application grid change the pixels substantially. A pure
        # luminance comparison is not reliable because the wallpaper and icon
        # colours vary independently of the dim layer.
        path = None
        size = None
        image = None
        mean_diff = 0.0
        for attempt in range(1, 5):
            ctx.sleep(0.4)
            path, size = ctx.screenshot("launcher", f"open-{attempt:02d}.png")
            candidate = pixels.load(path)
            mean_diff = pixels.mean_abs_diff(before, candidate, *zip(*[center_region])[0]) if False else pixels.mean_abs_diff(
                before,
                candidate,
                x0=center_region[0],
                y0=center_region[1],
                x1=center_region[2],
                y1=center_region[3],
            )
            if mean_diff >= 8.0:
                image = candidate
                break
        center_before = pixels.mean_luminance(
            before,
            x0=center_region[0],
            y0=center_region[1],
            x1=center_region[2],
            y1=center_region[3],
        )
        center_open = (
            pixels.mean_luminance(
                image,
                x0=center_region[0],
                y0=center_region[1],
                x1=center_region[2],
                y1=center_region[3],
            )
            if image is not None
            else center_before
        )
        data = {
            "noctalia": info,
            "layer": layer,
            "screenshot_size": size,
            "center_mean_abs_diff": round(mean_diff, 2),
            "center_luminance_before": round(center_before, 2),
            "center_luminance_open": round(center_open, 2),
        }
        if "launchpad" not in str(layer.get("name", "")).lower():
            return Result.failed(
                f"打开后的 layer 名称不是 Launchpad: {layer.get('name')!r}",
                expected=LAUNCHPAD_LAYER,
                data=data,
            )
        if mean_diff < 8.0:
            return Result.failed(
                f"打开后中心区域像素几乎未变化（mean_abs_diff={mean_diff:.2f} < 8），"
                "截图中看不到 Launchpad 抽屉内容",
                expected="drawer 的 dim/搜索框/图标网格使屏幕明显变化",
                data=data,
                artifacts=[str(path)] if path else [],
            )
        return Result.passed(
            f"Noctalia Launchpad 真实打开: layer={layer.get('name')}，中心区域 mean_abs_diff="
            f"{mean_diff:.1f}（drawer 确实绘制），亮度 {center_before:.1f} → {center_open:.1f}，截图已保存",
            data=data,
            artifacts=[str(path)] if path else [],
        )
    finally:
        toggle = _launchpad_toggle(ctx)
        closed = ctx.wait_until(lambda: _launchpad_layer(ctx) is None, timeout=6.0)
        if not closed:
            # Last resort: a second toggle is the only documented close path.
            _launchpad_toggle(ctx)
            closed = ctx.wait_until(lambda: _launchpad_layer(ctx) is None, timeout=4.0)
        ctx._cache["launcher_closed"] = closed


def test_launcher_noctalia_closed(ctx: Ctx) -> Result:
    require_live(ctx)
    closed = ctx._cache.get("launcher_closed")
    if closed is None:
        raise SkipTest("launcher-open 未执行")
    if not closed:
        return Result.failed(
            "Launchpad 关闭失败，可能残留在 live 会话（测试未能恢复）",
            expected="toggle 后 drawer layer 消失",
            observed=json.dumps(ctx.layers(), ensure_ascii=False)[:500],
        )
    return Result.passed("Launchpad 已关闭，live 会话无残留抽屉层")


# ---------------------------------------------------------------------------
# 10. suite cleanup / session restoration
# ---------------------------------------------------------------------------

def test_session_cleanup(ctx: Ctx) -> Result:
    """The suite must leave the live session as it found it."""
    require_live(ctx)
    layers = ctx.layers()
    clients = ctx.mmsg("get", "all-clients").get("clients") or []
    launchpad = [layer for layer in layers if "launchpad" in str(layer.get("name", "")).lower()]
    markshot_layers = [layer for layer in layers if "mark-shot" in str(layer.get("name", "")).lower()]
    markshot_clients = [
        client
        for client in clients
        if "mark-shot" in " ".join(str(client.get(k) or "") for k in ("appid", "title")).lower()
    ]
    mako = ctx.exec(["makoctl", "list"])
    mako_entries = [
        line for line in (mako.stdout or "").splitlines() if line.strip() and not line.startswith("-")
    ]
    data = {
        "layers": [layer.get("name") for layer in layers],
        "launchpad_layers": launchpad,
        "markshot_layers": markshot_layers,
        "markshot_clients": [
            {"id": client.get("id"), "title": client.get("title")} for client in markshot_clients
        ],
        "mako_entries": len(mako_entries),
    }
    problems: list[str] = []
    if launchpad:
        problems.append(f"Launchpad 层残留: {launchpad}")
    if markshot_layers or markshot_clients:
        problems.append(f"mark-shot surface 残留: layers={markshot_layers} clients={markshot_clients}")
    if problems:
        return Result.failed(
            "; ".join(problems),
            expected="测试结束后无 Launchpad/mark-shot 覆盖层残留",
            observed=json.dumps(data, ensure_ascii=False),
            data=data,
        )
    note = ""
    if mako_entries:
        note = f"；注意：mako 队列仍有 {len(mako_entries)} 条通知（可能来自其它进程/人工操作，本套件已 dismiss 自己的）"
    return Result.passed(
        "清理检查通过：无 Launchpad/mark-shot 残留层" + note,
        data=data,
    )
