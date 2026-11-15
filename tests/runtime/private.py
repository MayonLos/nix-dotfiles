"""Private headless compositor checks: login greeter and tray rendering.

Isolation contract (mirrors the repository's preview harness, re-implemented
here so the suite does not depend on ``.work``):

* private ``HOME`` and XDG dirs under a fresh 0700 ``/tmp`` root
* private session D-Bus from a generated ``dbus-daemon`` config; the system bus
  points at a deliberately missing socket
* headless wlroots output only; no live ``WAYLAND_DISPLAY``/``SWAYSOCK``/``DISPLAY``
  is inherited
* no sudo, no systemd/logind, no network, no second compositor on the live seat

Every spawned process is killed and the temporary root is removed before the
check returns, including on failure.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

from . import pixels
from .support import (
    Ctx,
    Result,
    SkipTest,
    TestFailure,
    which,
)

SYSTEM_BIN = "/run/current-system/sw/bin"
GREETER_SWAY_CONF = Path("/etc/greetd/sway.conf")


def discover_sway_tools() -> tuple[str | None, str | None]:
    """Find sway and swaymsg.

    sway is not in the user profile on this host, but the installed greeter
    configuration names the locked sway store path, so reuse exactly that build
    for private headless sessions when PATH has no sway.
    """
    sway = which("sway")
    swaymsg = which("swaymsg")
    if sway and swaymsg:
        return sway, swaymsg
    try:
        text = GREETER_SWAY_CONF.read_text(encoding="utf-8")
    except OSError:
        return sway, swaymsg
    for match in re.finditer(r"(/nix/store/[^\s']+)/bin/swaymsg\b", text):
        binary_dir = Path(match.group(1)) / "bin"
        candidate = binary_dir / "swaymsg"
        if swaymsg is None and candidate.is_file():
            swaymsg = str(candidate)
        candidate = binary_dir / "sway"
        if sway is None and candidate.is_file():
            sway = str(candidate)
    if sway is None:
        for match in re.finditer(r"(/nix/store/[^\s']+)/bin/sway(?!msg)", text):
            candidate = Path(match.group(1)) / "bin" / "sway"
            if candidate.is_file():
                sway = str(candidate)
                break
    return sway, swaymsg


def _tmp_root(prefix: str) -> Path:
    import uuid

    root = Path("/tmp") / f"runtime-e2e-{prefix}-{uuid.uuid4().hex[:8]}"
    root.mkdir(mode=0o700, parents=True)
    return root


def _sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


class PrivateSession:
    """A fully isolated private headless Sway + session D-Bus."""

    def __init__(self, ctx: Ctx, category: str, label: str):
        self.ctx = ctx
        self.category = category
        self.label = label
        self.root: Path | None = None
        self.env: dict[str, str] = {}
        self.sway: subprocess.Popen | None = None
        self.dbus: subprocess.Popen | None = None
        self.extra: list[subprocess.Popen] = []
        self.wayland_socket: str | None = None
        self.sway_log: Path | None = None

    # -- lifecycle ---------------------------------------------------------
    def __enter__(self) -> "PrivateSession":
        self.root = _tmp_root(self.label.replace("/", "-"))
        for name in (
            "home",
            "config",
            "cache",
            "state",
            "data",
            "runtime",
            "dbus",
            "no-services",
            "logs",
            "out",
        ):
            (self.root / name).mkdir(mode=0o700)
        os.chmod(self.root / "runtime", 0o700)
        os.chmod(self.root / "dbus", 0o700)
        self._start_dbus()
        return self

    def _start_dbus(self) -> None:
        assert self.root is not None
        daemon = which("dbus-daemon") or f"{SYSTEM_BIN}/dbus-daemon"
        if not Path(daemon).is_file():
            raise SkipTest("找不到 dbus-daemon，无法建立私有 session bus")
        conf = self.root / "dbus-session.conf"
        conf.write_text(
            "<!DOCTYPE busconfig PUBLIC '-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN'\n"
            " 'http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd'>\n"
            "<busconfig>\n"
            "  <type>session</type>\n"
            f"  <listen>unix:dir={self.root / 'dbus'}</listen>\n"
            "  <auth>EXTERNAL</auth>\n"
            f"  <servicedir>{self.root / 'no-services'}</servicedir>\n"
            "  <policy context='default'>\n"
            "    <allow user='*'/>\n"
            "    <allow own='*'/>\n"
            "    <allow send_destination='*'/>\n"
            "    <allow receive_sender='*'/>\n"
            "  </policy>\n"
            "</busconfig>\n",
            encoding="utf-8",
        )
        log = (self.root / "logs" / "dbus.log").open("w", encoding="utf-8")
        self.dbus = subprocess.Popen(
            [daemon, f"--config-file={conf}", "--print-address=1", "--nofork"],
            stdout=subprocess.PIPE,
            stderr=log,
            text=True,
            start_new_session=True,
        )
        assert self.dbus.stdout is not None
        address = self.dbus.stdout.readline().strip()
        if not address.startswith("unix:"):
            raise TestFailure(f"私有 dbus-daemon 未返回地址: {address!r}")
        self.env = {
            "HOME": str(self.root / "home"),
            "XDG_CONFIG_HOME": str(self.root / "config"),
            "XDG_CACHE_HOME": str(self.root / "cache"),
            "XDG_STATE_HOME": str(self.root / "state"),
            "XDG_DATA_HOME": str(self.root / "data"),
            "XDG_RUNTIME_DIR": str(self.root / "runtime"),
            "XDG_SESSION_TYPE": "wayland",
            "XDG_CURRENT_DESKTOP": "sway",
            "XDG_SESSION_DESKTOP": "sway",
            "DBUS_SESSION_BUS_ADDRESS": address,
            "DBUS_SYSTEM_BUS_ADDRESS": f"unix:path={self.root / 'missing-system-bus'}",
            "WLR_BACKENDS": "headless",
            "WLR_RENDERER": "pixman",
            "WLR_LIBINPUT_NO_DEVICES": "1",
            "LIBGL_ALWAYS_SOFTWARE": "1",
            "GTK_THEME": "Adwaita:dark",
            "XCURSOR_THEME": "Bibata-Modern-Ice",
            "XCURSOR_SIZE": "24",
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
            "PATH": f"{SYSTEM_BIN}:/usr/bin:/bin",
        }
        self.dbus_env = self.env

    def __exit__(self, exc_type, exc, tb) -> None:
        self.stop()

    def stop(self) -> None:
        for proc in reversed(self.extra):
            self._terminate(proc)
        self._terminate(self.sway)
        self._terminate(self.dbus)
        if self.root is not None and self.root.exists():
            # Keep the compositor log as evidence, then remove the private root.
            if self.sway_log is not None and self.sway_log.exists():
                target = self.ctx.artifact(self.category, f"{self.label.replace('/', '-')}-sway.log")
                try:
                    shutil.copyfile(self.sway_log, target)
                except OSError:
                    pass
            shutil.rmtree(self.root, ignore_errors=True)

    @staticmethod
    def _terminate(proc: subprocess.Popen | None) -> None:
        if proc is None or proc.poll() is not None:
            return
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            return
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

    # -- commands / rendering ---------------------------------------------
    def run(
        self, argv: list[str], *, timeout: float = 20.0, env: dict[str, str] | None = None
    ) -> subprocess.CompletedProcess:
        full_env = dict(self.env)
        if env:
            full_env.update(env)
        resolved = list(argv)
        if "/" not in resolved[0]:
            path = which(resolved[0])
            resolved[0] = path or resolved[0]
        return subprocess.run(
            resolved,
            capture_output=True,
            text=True,
            errors="replace",
            timeout=timeout,
            env=full_env,
            stdin=subprocess.DEVNULL,
        )

    def run_bytes(
        self, argv: list[str], *, input_bytes: bytes | None = None, timeout: float = 30.0
    ) -> subprocess.CompletedProcess:
        resolved = list(argv)
        if "/" not in resolved[0]:
            path = which(resolved[0])
            resolved[0] = path or resolved[0]
        return subprocess.run(
            resolved,
            input=input_bytes,
            capture_output=True,
            timeout=timeout,
            env=self.env,
        )

    def start_sway(self, config_text: str) -> None:
        assert self.root is not None
        sway_bin = self._sway_binary()
        conf = self.root / "sway.conf"
        conf.write_text(config_text, encoding="utf-8")
        self.sway_log = self.root / "logs" / "sway.log"
        log_handle = self.sway_log.open("w", encoding="utf-8")
        self.sway = subprocess.Popen(
            [sway_bin, "-c", str(conf), "-d"],
            stdout=log_handle,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            env=self.env,
            start_new_session=True,
            cwd=str(self.root),
        )
        ready = self.wait_until(lambda: self.sway.poll() is not None or self._find_wayland(), 20.0)
        if not ready or self.sway.poll() is not None:
            raise TestFailure(
                "headless sway 启动失败: "
                + self.sway_log.read_text(encoding="utf-8", errors="replace")[-1200:]
            )
        assert self.wayland_socket
        self.env["WAYLAND_DISPLAY"] = self.wayland_socket

    def _find_wayland(self) -> str | None:
        if self.root is None:
            return None
        for path in sorted((self.root / "runtime").glob("wayland-*")):
            if path.is_socket():
                self.wayland_socket = path.name
                return path.name
        return None

    def _sway_binary(self) -> str:
        sway, _swaymsg = discover_sway_tools()
        if sway:
            return sway
        raise SkipTest("找不到 sway 可执行文件，无法建立私有 headless 会话")

    def wait_until(self, predicate, timeout: float, interval: float = 0.1) -> bool:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try:
                if predicate():
                    return True
            except Exception:
                pass
            time.sleep(interval)
        return False

    def wait_log(self, pattern: str, timeout: float) -> bool:
        assert self.sway_log is not None
        expression = re.compile(pattern)
        return self.wait_until(
            lambda: expression.search(
                self.sway_log.read_text(encoding="utf-8", errors="replace")
            )
            is not None,
            timeout,
            interval=0.2,
        )

    def grim(self, path: Path, output: str = "HEADLESS-1") -> tuple[int, int]:
        grim = which("grim")
        if not grim:
            raise SkipTest("找不到 grim")
        result = self.run([grim, "-o", output, str(path)], timeout=30.0)
        if result.returncode != 0:
            raise TestFailure(f"私有会话 grim 失败: {result.stderr[:400]}")
        return pixels.image_size(path)

    def start(self, argv: list[str], *, log_name: str) -> subprocess.Popen:
        assert self.root is not None
        log = (self.root / "logs" / log_name).open("w", encoding="utf-8")
        resolved = list(argv)
        if "/" not in resolved[0]:
            resolved[0] = which(resolved[0]) or resolved[0]
        proc = subprocess.Popen(
            resolved,
            stdout=log,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
            env=self.env,
            start_new_session=True,
            cwd=str(self.root),
        )
        self.extra.append(proc)
        return proc

    def log_tail(self, name: str, limit: int = 1500) -> str:
        assert self.root is not None
        path = self.root / "logs" / name
        try:
            return path.read_text(encoding="utf-8", errors="replace")[-limit:]
        except OSError:
            return ""

    def process_alive(self, needle: str) -> bool:
        try:
            output = subprocess.run(
                ["ps", "-eo", "pid=,args="],
                capture_output=True,
                text=True,
                timeout=10,
            ).stdout
        except (OSError, subprocess.SubprocessError):
            return False
        return any(needle in line for line in output.splitlines())


# ---------------------------------------------------------------------------
# 8. login greeter (real gtkgreet binary + current /etc/greetd CSS)
# ---------------------------------------------------------------------------

def _discover_greeter() -> dict:
    if not GREETER_SWAY_CONF.is_file():
        raise SkipTest("/etc/greetd/sway.conf 不存在（本机未配置 greetd 登录屏）")
    text = GREETER_SWAY_CONF.read_text(encoding="utf-8")
    exec_lines = [
        line.strip()
        for line in text.splitlines()
        if line.strip().startswith("exec ") and "gtkgreet" in line
    ]
    if not exec_lines:
        raise SkipTest("/etc/greetd/sway.conf 中没有 gtkgreet exec 行")
    raw = exec_lines[0]
    command = raw[len("exec ") :].strip().strip("'").strip('"')
    # The config may chain `gtkgreet ...; swaymsg exit`; take the first command.
    first = shlex.split(command)[0].rstrip(";")
    argv = shlex.split(command)
    # Drop a trailing `; ...` token group if present.
    tokens: list[str] = []
    for token in argv:
        if token.endswith(";"):
            tokens.append(token[:-1])
            break
        tokens.append(token)
    gtkgreet = tokens[0]
    if not Path(gtkgreet).is_file():
        raise TestFailure(f"gtkgreet 可执行文件不存在: {gtkgreet}")
    css = next((tokens[i + 1] for i, tok in enumerate(tokens) if tok == "-s"), None)
    login_cmd = next((tokens[i + 1] for i, tok in enumerate(tokens) if tok == "-c"), None)
    return {
        "argv": tokens,
        "gtkgreet": gtkgreet,
        "css": css,
        "login_command": login_cmd,
        "sway_conf": str(GREETER_SWAY_CONF),
        "sway_conf_text": text,
    }


def test_greeter_render(ctx: Ctx) -> Result:
    info = _discover_greeter()
    css_path = Path(info["css"]) if info["css"] else None
    if not css_path or not css_path.is_file():
        return Result.failed(
            f"gtkgreet CSS 不存在: {info['css']!r}",
            expected="-s 指向存在的 CSS（/etc/greetd/gtkgreet.css）",
            data=info,
        )
    css_text = css_path.read_text(encoding="utf-8", errors="replace")
    css_sha = _sha256_text(css_text)
    css_copy = ctx.write_text("greeter", "gtkgreet-current.css", css_text)
    stub = Path(__file__).with_name("greetd_stub.py")
    if not stub.is_file():
        raise TestFailure("缺少 greetd_stub.py")

    with PrivateSession(ctx, "greeter", "greeter") as session:
        assert session.root is not None
        greetd_socket = session.root / "greetd.sock"
        stub_log = session.root / "logs" / "greetd-stub.log"
        session.env["GREETD_SOCK"] = str(greetd_socket)
        session.env["STUB_LOG"] = str(stub_log)
        stub_proc = subprocess.Popen(
            [sys.executable, str(stub), str(greetd_socket)],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            env=session.env,
            start_new_session=True,
        )
        session.extra.append(stub_proc)
        if not session.wait_until(lambda: greetd_socket.exists(), 10.0):
            return Result.failed(
                "greetd stub socket 未创建，gtkgreet 无法获得有效的 GREETD_SOCK",
                expected=str(greetd_socket),
            )
        # Same output/scale/background the installed greeter config uses.
        sway_conf = "\n".join(
            [
                "output HEADLESS-1 mode 2560x1600 scale 1.5",
                "output * bg #0e1013 solid_color",
                "seat seat0 xcursor_theme Bibata-Modern-Ice 24",
                "input type:keyboard xkb_layout us",
                "xwayland disable",
                f"exec '{' '.join(shlex.quote(tok) for tok in info['argv'])}'",
                "",
            ]
        )
        session.start_sway(sway_conf)
        layer_found = session.wait_log(r"new layer surface: namespace gtk-layer-shell", 25.0)
        if not layer_found:
            alive = session.process_alive(info["gtkgreet"])
            return Result.failed(
                "私有 headless sway 中 gtkgreet 未创建 gtk-layer-shell 表面"
                + ("（进程已退出）" if not alive else "（进程仍存活但未渲染）"),
                expected="gtkgreet 以 layer-shell 全屏渲染登录卡片",
                observed=session.log_tail("sway.log")[-1200:],
                artifacts=[str(css_copy)],
            )
        # gtkgreet paints its layer once mapped; give it a stable frame.
        time.sleep(1.2)
        shot = session.root / "out" / "greeter.png"
        size = session.grim(shot)
        target = ctx.artifact("greeter", "greeter-render.png")
        shutil.copyfile(shot, target)
        stub_text = session.log_tail("greetd-stub.log", 3000)
        greeter_alive = session.process_alive(info["gtkgreet"])
        logs = {
            "sway_config": sway_conf,
            "gtkgreet_argv": info["argv"],
            "css": str(css_path),
            "css_sha256": css_sha,
            "greetd_stub_log": stub_text,
        }
        ctx.write_text("greeter", "greeter-run.json", json.dumps(logs, ensure_ascii=False, indent=2))

    image = pixels.load(target)
    palette_colors = re.findall(r"#[0-9a-fA-F]{6}\b", css_text)
    palette_hits: dict[str, int] = {}
    for color in sorted(set(palette_colors)):
        rgb = tuple(int(color[index : index + 2], 16) for index in (1, 3, 5))
        count = pixels.count_near(image, rgb, tolerance=8)
        if count:
            palette_hits[color] = count
    center_ink = 0
    for y in range(int(image.height * 0.2), int(image.height * 0.8), 2):
        for x in range(int(image.width * 0.2), int(image.width * 0.8), 2):
            if pixels.luminance(image.pixel(x, y)) >= 140:
                center_ink += 1
    brightest_palette = max(palette_hits.values()) if palette_hits else 0
    data = {
        "screenshot": str(target),
        "screenshot_size": size,
        "css": str(css_path),
        "css_sha256": css_sha,
        "css_colors_found": palette_hits,
        "center_ink_pixels": center_ink,
        "greetd_stub_log": logs["greetd_stub_log"][:800],
        "greeter_process_alive_at_capture": greeter_alive,
    }
    problems: list[str] = []
    if size[0] != 2560 or size[1] not in (1599, 1600):
        problems.append(f"截图尺寸 {size} 不是 2560×1600 物理输出（headless 可能取整为 1599）")
    if not greeter_alive:
        problems.append("截图时 gtkgreet 进程已退出（渲染可能来自残留帧）")
    if center_ink < 200:
        problems.append(f"登录卡片中心区域亮色文字像素仅 {center_ink}，疑似未真实渲染")
    if brightest_palette < 300:
        problems.append(
            f"当前 CSS 的颜色在截图中最多只出现 {brightest_palette} 像素，"
            "无法证明渲染使用了 /etc/greetd/gtkgreet.css"
        )
    if problems:
        return Result.failed(
            "; ".join(problems),
            expected="真实 gtkgreet + 当前 /etc/greetd CSS 在私有 headless Sway 中渲染登录卡片",
            observed=json.dumps(data, ensure_ascii=False),
            data=data,
            artifacts=[str(target), str(css_copy)],
        )
    return Result.passed(
        f"gtkgreet 真实渲染: {size[0]}×{size[1]}，CSS {css_sha[:12]} 颜色命中 "
        f"{len(palette_hits)} 种（最多 {brightest_palette} px），中心亮色像素 {center_ink}",
        data=data,
        artifacts=[str(target), str(css_copy)],
    )


# ---------------------------------------------------------------------------
# 9. tray rendering (private) and tray menu (documented not-automated blocker)
# ---------------------------------------------------------------------------

TRAY_MIN_CONFIG = {
    "height": 30,
    "layer": "top",
    "modules-right": ["tray", "clock"],
    "tray": {"icon-size": 18, "spacing": 10},
    "clock": {"format": "{:L%H:%M}"},
}

TRAY_MIN_STYLE = """* {
  font-family: "Maple Mono NF CN";
  font-size: 13px;
  font-weight: Medium;
  color: #d7dae0;
  background: none;
  border-radius: 0;
  padding: 0;
  margin: 0;
}
#bar { background: none; margin: 0; padding: 0 12px; }
#clock { color: #d7dae0; padding: 0 12px; }
#tray { padding: 0 4px; }
"""


def _tray_config_files(ctx: Ctx) -> tuple[Path, Path]:
    config = ctx.artifact("tray", "min-bar.jsonc")
    style = ctx.artifact("tray", "min-bar.css")
    config.write_text(json.dumps(TRAY_MIN_CONFIG), encoding="utf-8")
    style.write_text(TRAY_MIN_STYLE, encoding="utf-8")
    return config, style


def test_tray_mangobar_render(ctx: Ctx) -> Result:
    mangobar = which("mangobar")
    if not mangobar:
        raise SkipTest("找不到 mangobar 可执行文件")
    config, style = _tray_config_files(ctx)
    with PrivateSession(ctx, "tray", "tray-render") as session:
        session.start_sway(
            "\n".join(
                [
                    "output HEADLESS-1 mode 2560x1600 scale 1.5",
                    "output * bg #0e1013 solid_color",
                    "xwayland disable",
                    "",
                ]
            )
        )
        session.start([mangobar, "-c", str(config), "-s", str(style)], log_name="mangobar.log")
        layer = session.wait_log(r"new layer surface: namespace mangobar", 15.0)
        if not layer:
            return Result.failed(
                "mangobar 在私有 headless sway 中未创建 layer surface",
                expected="namespace mangobar 的 layer surface",
                observed=session.log_tail("sway.log")[-1200:],
            )
        time.sleep(2.0)
        shot = session.root / "out" / "tray-bar.png"
        size = session.grim(shot)
        target = ctx.artifact("tray", "private-mangobar.png")
        shutil.copyfile(shot, target)
    image = pixels.load(target)
    width, height = image.width, image.height

    def non_background(x0: int, x1: int, y0: int, y1: int) -> int:
        background = (14, 16, 19)
        count = 0
        for y in range(y0, min(y1, height)):
            for x in range(x0, min(x1, width)):
                color = image.rgb(x, y)
                if sum(abs(color[i] - background[i]) for i in range(3)) > 18:
                    count += 1
        return count

    clock_pixels = non_background(int(width * 0.75), width, 0, 46)
    tray_pixels = non_background(0, int(width * 0.75), 0, 46)
    data = {
        "screenshot": str(target),
        "screenshot_size": size,
        "layer_created": True,
        "clock_region_pixels": clock_pixels,
        "tray_region_pixels": tray_pixels,
    }
    problems: list[str] = []
    if size[0] != 2560:
        problems.append(f"私有输出宽度 {size[0]} != 2560")
    if clock_pixels < 50:
        problems.append(f"右侧 clock 区域非背景像素仅 {clock_pixels}，mangobar 可能未绘制")
    if problems:
        return Result.failed(
            "; ".join(problems),
            expected="真实 mangobar 在私有 headless sway 中创建 layer 并绘制 clock",
            observed=json.dumps(data, ensure_ascii=False),
            data=data,
            artifacts=[str(target)],
        )
    return Result.passed(
        f"真实 mangobar 在私有 headless sway 中创建 layer surface 并绘制 clock"
        f"（右侧非背景像素 {clock_pixels}）",
        data=data,
        artifacts=[str(target)],
    )


def test_tray_menu_open(ctx: Ctx) -> Result:
    """Attempt the real tray context menu; record why it is not automatable yet.

    The decision is made from real evidence: the private Sway seat is inspected
    for pointer capability, and a synthetic cursor press is attempted through
    swaymsg. Mangobar also needs a real StatusNotifier item and Mango IPC for a
    full menu, so this check documents the blocker instead of pretending PASS.
    """
    sway, swaymsg = discover_sway_tools()
    evidence: dict[str, object] = {}
    if not sway or not swaymsg:
        raise SkipTest(
            "私有环境中找不到 sway/swaymsg；无法探测 tray 菜单输入路径"
        )
    with PrivateSession(ctx, "tray", "tray-menu") as session:
        session.start_sway(
            "\n".join(
                [
                    "output HEADLESS-1 mode 2560x1600 scale 1.5",
                    "output * bg #0e1013 solid_color",
                    "xwayland disable",
                    "",
                ]
            )
        )
        seats = session.run([swaymsg, "-t", "get_seats"], timeout=10.0)
        try:
            seats_json = json.loads(seats.stdout)
        except json.JSONDecodeError:
            seats_json = seats.stdout
        evidence["seats"] = seats_json
        capabilities: list[str] = []
        if isinstance(seats_json, list):
            for seat in seats_json:
                capabilities.extend(seat.get("capabilities", []))
        evidence["seat_capabilities"] = sorted(set(capabilities))
        pointer_available = "pointer" in capabilities
        evidence["pointer_capability"] = pointer_available
        set_result = session.run(
            [swaymsg, "seat", "-", "cursor", "set", "1280", "20"], timeout=10.0
        )
        press_result = session.run(
            [swaymsg, "seat", "-", "cursor", "press", "button1"], timeout=10.0
        )
        evidence["cursor_set_stderr"] = set_result.stderr.strip()
        evidence["press_exit"] = press_result.returncode
        evidence["press_stdout"] = press_result.stdout.strip()[:300]
        # Real mangobar renders, but without a pointer device no SNI menu can be
        # clicked. Keep the decision explicit and machine-checkable.
        evidence["mangobar_requires"] = [
            "Mango IPC (mmsg) for full bar modules",
            "a real StatusNotifierItem provider",
            "a wlr-virtual-pointer client to inject pointer events into the headless seat",
        ]
        artifact = ctx.write_text(
            "tray", "tray-menu-evidence.json", json.dumps(evidence, ensure_ascii=False, indent=2)
        )
    if not pointer_available:
        return Result.skipped(
            "未能自动验证 tray 菜单点击：私有 headless Sway 的 seat 没有 pointer capability"
            f"（seats.capabilities={evidence['seat_capabilities']}）；"
            "swaymsg seat - cursor set/press 返回成功但不会投递事件。"
            "真实 mangobar 的 tray 菜单还需要 Mango IPC + 真实 SNI item + wlr-virtual-pointer "
            "客户端（另一分支的 tray session-test 正在实现），本套件不重复。",
            data=evidence,
            artifacts=[str(artifact)],
        )
    return Result.skipped(
        "私有 headless seat 具备 pointer capability，但 mangobar tray 菜单的 SNI 提供者与 "
        "Mango IPC 尚未接入，仍需真实 SNI item + 点击坐标检测；当前未实现完整菜单断言。",
        data=evidence,
        artifacts=[str(artifact)],
    )
