#!/usr/bin/env python3
"""Runtime E2E suite for the NixOS + Mango desktop.

This suite is deliberately *not* a Nix evaluation check. Every item shells out
to the real programs, takes real screenshots with ``grim`` and inspects real
files/D-Bus state. It is safe to run from the live graphical session: it never
uses sudo, never restarts system/user units, never writes to ``~/.config``, and
restores the transient state it touches (clipboard, volume, notifications,
Launchpad/Mark-Shot surfaces it opened itself).

Usage:
    python3 tests/runtime/run.py
    python3 tests/runtime/run.py --categories services,bar,osd
    python3 tests/runtime/run.py --artifact-dir /tmp/e2e --json /tmp/report.json
    python3 tests/runtime/run.py --list

Exit code: 0 when no check FAILs (SKIP is reported but does not fail the run),
1 when at least one check FAILs, 2 for a harness-level error.
"""

from __future__ import annotations

import argparse
import datetime as _datetime
import json
import os
import platform
import subprocess
import sys
import time
import traceback
from pathlib import Path

RUNTIME_DIR = Path(__file__).resolve().parent
ROOT = RUNTIME_DIR.parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tests.runtime import live, private, support  # noqa: E402
from tests.runtime.support import (  # noqa: E402
    STATUS_FAIL,
    STATUS_PASS,
    STATUS_SKIP,
    Ctx,
    Result,
    SkipTest,
    TestFailure,
)

SUITE_NAME = "desktop-runtime-e2e"
SUITE_VERSION = 1

# (id, category, title, callable)
TESTS = [
    # 1. system / services
    ("services/user-units", "services", "用户 session 单元全部 active", live.test_services_user_units),
    ("services/system-backend", "services", "系统级 swayosd-libinput-backend active", live.test_services_system_backend),
    ("services/failed-units", "services", "systemctl --user --failed 为空", live.test_services_failed_units),
    ("services/restart-stability", "services", "用户单元无崩溃重启循环", live.test_services_restart_stability),
    ("services/journal", "services", "最近 journal 错误分类（已知噪音 vs 真实错误）", live.test_services_journal_classified),
    ("services/session-env", "services", "XDG_SESSION_ID 注入 user manager（R41 复核项）", live.test_services_session_env),
    # 2. top bar
    ("bar/config", "bar", "mangobar 配置契约（30px/透明/no_blur/模块）", live.test_bar_config),
    ("bar/transparency", "bar", "顶栏像素透明（壁纸透出、无填充）", live.test_bar_transparency),
    ("bar/modules", "bar", "顶栏左/中/右模块真实绘制", live.test_bar_modules_ink),
    ("bar/geometry", "bar", "顶栏 30 逻辑 px = 45 物理 px（窗口顶边反推）", live.test_bar_geometry),
    ("bar/tray-items", "bar", "StatusNotifierWatcher 有真实 tray item", live.test_bar_tray_items),
    # 3. OSD
    ("osd/config", "osd", "swayosd 配置（top_margin 公式/show_percentage）", live.test_osd_config),
    ("osd/caps-lock", "osd", "Caps Lock OSD 真实出现/几何/颜色/消失", live.test_osd_caps_lock),
    ("osd/num-lock", "osd", "Num Lock OSD 真实出现/几何/颜色/消失", live.test_osd_num_lock),
    ("osd/output-volume", "osd", "音量 OSD + 蓝色进度条真实出现/恢复音量", live.test_osd_output_volume),
    # 4. notifications
    ("notifications/config", "notifications", "mako 配置契约 + on-notify 声音命令", live.test_notifications_config),
    ("notifications/daemon", "notifications", "mako 独占 org.freedesktop.Notifications", live.test_notifications_daemon),
    ("notifications/card", "notifications", "notify-send 真实卡片几何/颜色", live.test_notifications_card),
    ("notifications/dismissed", "notifications", "makoctl dismiss 后无残留", live.test_notifications_dismissed),
    ("notifications/on-notify-sound", "notifications", "on-notify 声音命令真实执行", live.test_notifications_on_notify_sound),
    # 5. clipboard
    ("clipboard/text-roundtrip", "clipboard", "文本 wl-copy→cliphist→wl-paste 往返", live.test_clipboard_text_roundtrip),
    ("clipboard/image-roundtrip", "clipboard", "PNG wl-copy→cliphist decode→wl-paste 无损往返", live.test_clipboard_image_roundtrip),
    ("clipboard/super-v-preview", "clipboard", "Super+V 用 cliphist-tui 预览并自动粘贴", live.test_clipboard_super_v_preview),
    # 6. mark-shot
    ("mark-shot/version", "mark-shot", "真实 mark-shot --version", live.test_markshot_version),
    ("mark-shot/list-displays", "mark-shot", "--list-displays 输出与物理/逻辑尺寸", live.test_markshot_list_displays),
    ("mark-shot/capture-size", "mark-shot", "--capture-to PNG 物理尺寸 == grim（已知 bug）", live.test_markshot_capture_size),
    ("mark-shot/copy", "mark-shot", "-m -f -t c 复制 PNG 尺寸 == grim（已知 bug）", live.test_markshot_copy),
    ("mark-shot/editor", "mark-shot", "--fullscreen 编辑器真实出现（测试进程立即关闭）", live.test_markshot_editor),
    ("mark-shot/editor-cleanup", "mark-shot", "mark-shot 编辑器无残留", live.test_markshot_editor_closed),
    # 7. launcher / Noctalia
    ("launcher/binding", "launcher", "Alt+Space 为 fuzzel --no-icons，Super+A 无启动绑定", live.test_launcher_binding),
    ("launcher/overlay-open", "launcher", "mayon-launcher 仅在会话仍绑定时打开", live.test_launcher_overlay),
    ("clipboard/overlay-open", "clipboard", "mayon-clipboard 仅在会话仍绑定时打开", live.test_clipboard_overlay),
    ("launcher/noctalia-open", "launcher", "Noctalia Launchpad 真实打开 + 截图像素", live.test_launcher_noctalia_open),
    ("launcher/noctalia-closed", "launcher", "Launchpad 关闭后无残留层", live.test_launcher_noctalia_closed),
    # 8. greeter
    ("greeter/render", "greeter", "私有 headless Sway + 真实 gtkgreet + 当前 CSS 渲染", private.test_greeter_render),
    # 9. tray
    ("tray/mangobar-render", "tray", "私有 headless Sway 中真实 mangobar 渲染", private.test_tray_mangobar_render),
    ("tray/menu-open", "tray", "tray 菜单点击（未能自动验证，记录证据）", private.test_tray_menu_open),
    # 10. suite cleanup
    ("session/cleanup", "session", "测试后 live 会话无覆盖层残留", live.test_session_cleanup),
]

CATEGORIES = []
for _test_id, _category, _title, _fn in TESTS:
    if _category not in CATEGORIES:
        CATEGORIES.append(_category)


# ---------------------------------------------------------------------------
# environment snapshot
# ---------------------------------------------------------------------------

def _run_quiet(argv: list[str], timeout: float = 10.0) -> str:
    try:
        proc = subprocess.run(
            argv,
            capture_output=True,
            text=True,
            errors="replace",
            timeout=timeout,
            stdin=subprocess.DEVNULL,
            env=support.child_env(),
        )
        return (proc.stdout or proc.stderr or "").strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def gather_environment(ctx: Ctx) -> dict:
    environment: dict[str, object] = {
        "hostname": platform.node(),
        "kernel": platform.release(),
        "python": platform.python_version(),
        "repo_root": str(ROOT),
        "cwd": os.getcwd(),
        "time": _datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "system_generation": os.path.realpath("/run/current-system"),
        "nixos_version": _run_quiet(["nixos-version"]),
    }
    try:
        environment["git"] = {
            "commit": _run_quiet(["git", "-C", str(ROOT), "rev-parse", "HEAD"]),
            "branch": _run_quiet(["git", "-C", str(ROOT), "rev-parse", "--abbrev-ref", "HEAD"]),
            "status_short": _run_quiet(["git", "-C", str(ROOT), "status", "--short"]),
            "base": "804af3f (test/runtime-e2e)",
        }
    except Exception:  # pragma: no cover - environment only
        environment["git"] = {}
    wayland_env, reason = ctx.wayland_env()
    environment["session"] = {
        "WAYLAND_DISPLAY": os.environ.get("WAYLAND_DISPLAY"),
        "XDG_RUNTIME_DIR": os.environ.get("XDG_RUNTIME_DIR"),
        "DBUS_SESSION_BUS_ADDRESS": os.environ.get("DBUS_SESSION_BUS_ADDRESS"),
        "live_session_available": not reason,
        "live_session_skip_reason": reason,
    }
    for key, argv in (
        ("noctalia", ["noctalia", "--version"]),
        ("mark-shot", ["mark-shot", "--version"]),
        ("grim", ["grim", "--version"]),
        ("mmsg_version", ["mmsg", "get", "version"]),
    ):
        environment[key] = _run_quiet(argv)
    if not reason:
        try:
            monitor = ctx.monitor()
            environment["monitor"] = {
                key: monitor.get(key)
                for key in ("name", "width", "height", "scale", "active")
            }
            focused = ctx.focused_client()
            if focused:
                environment["focused_client"] = {
                    key: focused.get(key)
                    for key in ("id", "appid", "title", "y", "is_fullscreen", "is_floating")
                }
            environment["layers"] = [layer.get("name") for layer in ctx.layers()]
        except (TestFailure, SkipTest) as exc:
            environment["monitor_error"] = str(exc)
    try:
        manager_env = ctx.exec(["systemctl", "--user", "show-environment"], timeout=10.0)
        for line in (manager_env.stdout or "").splitlines():
            if line.startswith("XDG_SESSION_ID="):
                environment["XDG_SESSION_ID"] = line.partition("=")[2].strip()
    except Exception:  # environment only
        pass
    try:
        system_bus = ctx.exec(
            ["busctl", "--system", "list", "--no-legend"], timeout=15.0, label="busctl --system list"
        )
        environment["system_bus_swayosd"] = [
            line.strip()
            for line in (system_bus.stdout or "").splitlines()
            if "erikreider.swayosd" in line
        ]
    except Exception:  # environment only
        pass
    try:
        journal = ctx.exec(
            ["journalctl", "-b", "-q", "--no-pager", "-o", "cat", "--since", "-1h"],
            timeout=20.0,
        )
        environment["coredumps_last_hour"] = sum(
            1 for line in (journal.stdout or "").splitlines() if "dumped core" in line
        )
    except Exception:  # environment only
        pass
    palette = ctx.palette()
    environment["palette"] = {
        "source": palette.get("_source"),
        "surface": palette.get("surface"),
        "brightFg": palette.get("brightFg"),
        "blue": palette.get("blue"),
        "border": palette.get("border"),
    }
    environment["config_files"] = {
        key: {"path": str(path), "exists": path.exists(), "symlink": str(path.resolve()) if path.is_symlink() else None}
        for key, path in live._live_config_paths(ctx).items()
    }
    return environment


# ---------------------------------------------------------------------------
# execution
# ---------------------------------------------------------------------------

def select_tests(
    categories: list[str] | None, only: list[str] | None, exclude: list[str] | None
) -> list[tuple[str, str, str, object]]:
    selected = []
    for test_id, category, title, function in TESTS:
        if categories and category not in categories and not any(
            test_id == value or test_id.startswith(value + "/") for value in categories
        ):
            continue
        if only and not any(
            test_id == value or test_id.startswith(value + "/") or test_id.endswith("/" + value)
            for value in only
        ):
            continue
        if exclude and any(
            test_id == value or test_id.startswith(value + "/") or test_id.endswith("/" + value)
            for value in exclude
        ):
            continue
        selected.append((test_id, category, title, function))
    return selected


def run_test(ctx: Ctx, test_id: str, category: str, title: str, function) -> dict:
    started = time.monotonic()
    result: Result
    try:
        result = function(ctx)
        if not isinstance(result, Result):
            result = Result.failed(f"测试函数返回了 {type(result)!r} 而不是 Result")
    except SkipTest as exc:
        result = Result.skipped(str(exc.reason))
    except TestFailure as exc:
        result = Result.failed(str(exc))
    except Exception as exc:  # harness bug, still recorded honestly
        result = Result.failed(
            f"未捕获异常: {exc.__class__.__name__}: {exc}\n{traceback.format_exc()[-1500:]}"
        )
    duration = time.monotonic() - started
    if result.duration == 0.0:
        result.duration = round(duration, 3)
    record = {
        "id": test_id,
        "category": category,
        "title": title,
        "status": result.status,
        "detail": result.detail,
        "expected": result.expected,
        "observed": result.observed,
        "data": result.data,
        "artifacts": result.artifacts,
        "duration_s": round(result.duration, 3),
    }
    return record


def summary_by_category(records: list[dict]) -> dict[str, dict[str, int]]:
    summary: dict[str, dict[str, int]] = {}
    for record in records:
        category = record["category"]
        row = summary.setdefault(category, {STATUS_PASS: 0, STATUS_FAIL: 0, STATUS_SKIP: 0})
        row[record["status"]] = row.get(record["status"], 0) + 1
    return summary


def top_summary(records: list[dict]) -> dict[str, int]:
    counts = {STATUS_PASS: 0, STATUS_FAIL: 0, STATUS_SKIP: 0}
    for record in records:
        counts[record["status"]] = counts.get(record["status"], 0) + 1
    counts["tests"] = len(records)
    return counts


def print_record(record: dict, verbose: bool) -> None:
    status = record["status"]
    detail = (record["detail"] or "").replace("\n", " ")
    if not verbose and len(detail) > 220:
        detail = detail[:217] + "..."
    print(f"[{status:<4}] {record['id']:<32} {detail}")
    if verbose:
        for artifact in record.get("artifacts") or []:
            print(f"          artifact: {artifact}")


def write_report(report: dict, ctx: Ctx, json_path: Path | None) -> Path:
    report_path = ctx.artifact_dir / "report.json"
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    if json_path:
        json_path.parent.mkdir(parents=True, exist_ok=True)
        json_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    return report_path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="tests/runtime/run.py",
        description="Desktop runtime E2E suite (real commands, real screenshots).",
    )
    parser.add_argument("--categories", help="逗号分隔的类别: " + ",".join(CATEGORIES))
    parser.add_argument("--only", help="只跑指定 test id / 后缀（逗号分隔）")
    parser.add_argument("--exclude", help="排除指定 test id / 后缀（逗号分隔）")
    parser.add_argument("--artifact-dir", help="PNG/JSON 证据目录（默认 .work/e2e/<时间戳>）")
    parser.add_argument("--json", help="额外写一份 JSON 报告到该路径")
    parser.add_argument("--list", action="store_true", help="列出全部测试后退出")
    parser.add_argument("--verbose", action="store_true", help="打印每条详情的完整文本与 artifact")
    parser.add_argument("--fail-fast", action="store_true", help="首个 FAIL 后停止")
    args = parser.parse_args(argv)

    if args.list:
        for test_id, category, title, _fn in TESTS:
            print(f"{test_id:<32} [{category}] {title}")
        return 0

    categories = [item.strip() for item in (args.categories or "").split(",") if item.strip()] or None
    only = [item.strip() for item in (args.only or "").split(",") if item.strip()] or None
    exclude = [item.strip() for item in (args.exclude or "").split(",") if item.strip()] or None
    selected = select_tests(categories, only, exclude)
    if not selected:
        print("没有匹配的测试。--list 查看全部测试。", file=sys.stderr)
        return 2

    stamp = _datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    artifact_dir = (
        Path(args.artifact_dir).expanduser().resolve()
        if args.artifact_dir
        else ROOT / ".work" / "e2e" / stamp
    )
    artifact_dir.mkdir(parents=True, exist_ok=True)
    ctx = Ctx(ROOT, artifact_dir, verbose=args.verbose)
    started_wall = _datetime.datetime.now().astimezone()
    started = time.monotonic()

    print("=" * 100)
    print(f"desktop runtime E2E  |  repo={ROOT}")
    print(f"artifacts = {artifact_dir}")
    environment = gather_environment(ctx)
    (artifact_dir / "environment.json").write_text(
        json.dumps(environment, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    session = environment.get("session", {})
    print(
        f"system = {environment.get('system_generation')}\n"
        f"git    = {environment.get('git', {}).get('branch')} @ "
        f"{str(environment.get('git', {}).get('commit'))[:12]} "
        f"dirty={'yes' if environment.get('git', {}).get('status_short') else 'no'}\n"
        f"live session = {session.get('live_session_available')} "
        f"{session.get('live_session_skip_reason') or ''}"
    )
    print("=" * 100)

    records: list[dict] = []
    for test_id, category, title, function in selected:
        record = run_test(ctx, test_id, category, title, function)
        records.append(record)
        print_record(record, args.verbose)
        if args.fail_fast and record["status"] == STATUS_FAIL:
            print("--fail-fast: 遇到 FAIL，停止执行剩余测试", file=sys.stderr)
            break

    finished = time.monotonic()
    counts = top_summary(records)
    report = {
        "suite": SUITE_NAME,
        "version": SUITE_VERSION,
        "started_at": started_wall.isoformat(timespec="seconds"),
        "finished_at": _datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
        "duration_s": round(finished - started, 2),
        "argv": sys.argv[1:],
        "environment": environment,
        "artifacts_dir": str(artifact_dir),
        "summary": counts,
        "by_category": summary_by_category(records),
        "tests": records,
    }
    report_path = write_report(report, ctx, Path(args.json).expanduser() if args.json else None)

    print("=" * 100)
    print(f"{'CATEGORY':<16} {'PASS':>5} {'FAIL':>5} {'SKIP':>5}")
    for category, row in report["by_category"].items():
        print(f"{category:<16} {row.get(STATUS_PASS, 0):>5} {row.get(STATUS_FAIL, 0):>5} {row.get(STATUS_SKIP, 0):>5}")
    print("-" * 100)
    print(
        f"{'TOTAL':<16} {counts.get(STATUS_PASS, 0):>5} {counts.get(STATUS_FAIL, 0):>5} "
        f"{counts.get(STATUS_SKIP, 0):>5}"
    )
    failures = [record for record in records if record["status"] == STATUS_FAIL]
    skips = [record for record in records if record["status"] == STATUS_SKIP]
    if failures:
        print("\nFAIL 清单（真实失败，需要修复或作为基线记录）:")
        for record in failures:
            print(f"  - {record['id']}: {record['detail'].splitlines()[0][:300]}")
    if skips:
        print("\nSKIP 清单（环境缺失或未自动化，禁止算作通过）:")
        for record in skips:
            print(f"  - {record['id']}: {(record['detail'] or '').splitlines()[0][:300]}")
    print(f"\nJSON report: {report_path}")
    print(f"PNG 证据:   {artifact_dir}")
    return 0 if not failures else 1


if __name__ == "__main__":
    raise SystemExit(main())
