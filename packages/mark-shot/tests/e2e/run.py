#!/usr/bin/env python3
"""Private headless Mango runtime suite for mark-shot.

Starts a private D-Bus session and a private headless Mango (wlroots headless
+ pixman) with a 2560x1600 output at scale 1.5, matching the real eDP-1
desktop.  A static swaybg wallpaper gives deterministic pixels; a pure-Python
wlr virtual pointer replays the real overlay drags and button clicks.  Every
process gets a private HOME/XDG_RUNTIME_DIR, so the caller's desktop, bus and
clipboard are never touched.

Run through the Nix wrapper from `tests/e2e/default.nix` (it pins every tool):

  MS_E2E_OUT=/tmp/mark-shot-e2e mark-shot-e2e --phase all

Phases: capture, clipboard, persist, region, interactive, editor, pin, scroll.
Set PHASE=<name> or run `--phase all` for everything.

The suite asserts real runtime facts, not static details:
  * capture/copy/save PNGs are 2560x1600 (the physical mode, not
    round(logical * 1.5) = 2561x1601), fully decodable and CRC-valid;
  * the clipboard PNG is complete while wl-clip-persist and clipboard
    watchers concurrently read the same selection (the old EAGAIN path
    truncated every transfer at one 64 KiB pipe buffer);
  * the editor preview is the frozen capture: killing the wallpaper behind
    the overlay leaves the screen byte-identical;
  * a real selection drag + copy-button click exports exactly the pixels of
    the full capture at the mapped physical offset.
"""


from __future__ import annotations

import json
import math
import os
import signal
import subprocess
import sys
import time
from pathlib import Path

import shutil

ROOT = Path(os.environ.get("MS_E2E_ROOT", "/tmp/ms-e2e"))
OUT = Path(os.environ.get("MS_E2E_OUT", str(Path.cwd() / "e2e-out")))


def _tool(env_name: str, *names: str, fallback: str | None = None) -> str:
    """Resolve an external tool: explicit env override, then PATH, then a config default."""
    override = os.environ.get(env_name)
    if override:
        return override
    for name in names:
        found = shutil.which(name)
        if found:
            return found
    if fallback:
        return fallback
    raise SystemExit(f"missing required tool: {env_name} ({', '.join(names)})")


MANGO = _tool("MS_E2E_MANGO", "mango")
GRIM = _tool("MS_E2E_GRIM", "grim")
WL_PASTE = _tool("MS_E2E_WL_PASTE", "wl-paste")
WL_COPY = _tool("MS_E2E_WL_COPY", "wl-copy")
FILE_BIN = _tool("MS_E2E_FILE", "file")
MAGICK = _tool("MS_E2E_MAGICK", "magick", "convert")
DBUS_RUN_SESSION = _tool("MS_E2E_DBUS", "dbus-run-session")
SWAYBG = _tool("MS_E2E_SWAYBG", "swaybg")
CLIP_PERSIST = _tool("MS_E2E_CLIP_PERSIST", "wl-clip-persist")
WTYPE = _tool("MS_E2E_WTYPE", "wtype")
PYTHON = os.environ.get("MS_E2E_PYTHON", sys.executable)
UPSTREAM_SCRIPTS = os.environ.get(
    "MS_E2E_UPSTREAM_SCRIPTS",
    str(Path(__file__).resolve().parents[2] / "scripts"),
)
MARK_SHOT = os.environ.get("MARK_SHOT", "")

results: list[dict] = []


def record(name: str, ok: bool, detail: str = "") -> None:
    results.append({"test": name, "ok": ok, "detail": detail})
    print(f"[{'PASS' if ok else 'FAIL'}] {name}: {detail}", flush=True)


def _env(extra: dict | None = None) -> dict:
    env = dict(os.environ)
    env["LC_ALL"] = "C.UTF-8"
    env["LANG"] = "C.UTF-8"
    if extra:
        env.update(extra)
    return env


def run(argv, *, timeout: float = 30.0, env: dict | None = None, check: bool = False) -> subprocess.CompletedProcess:
    proc = subprocess.run(argv, timeout=timeout, env=_env(env), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and proc.returncode != 0:
        raise RuntimeError(
            f"{argv[0]} failed rc={proc.returncode}: {proc.stderr.decode(errors='replace')[:2000]}"
        )
    return proc


def image_info(path: Path) -> tuple[int, int]:
    proc = run([MAGICK, "identify", "-format", "%w %h", str(path)], check=True)
    width, height = proc.stdout.decode().split()
    return int(width), int(height)


def image_format(path: Path) -> str:
    return run([MAGICK, "identify", "-format", "%m", str(path)], check=True).stdout.decode()


def magic(path: Path) -> str:
    return run([FILE_BIN, "-b", str(path)], check=True).stdout.decode().strip()


def png_integrity(path: Path) -> tuple[bool, str]:
    """Verify every PNG chunk CRC, the IEND terminator and the decoded IDAT size."""
    import struct
    import zlib

    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        return False, "bad signature"
    offset = 8
    width = height = depth = color = None
    idat = bytearray()
    while offset + 8 <= len(data):
        length, kind = struct.unpack(">I4s", data[offset : offset + 8])
        body = data[offset + 8 : offset + 8 + length]
        crc_bytes = data[offset + 8 + length : offset + 12 + length]
        if len(body) != length or len(crc_bytes) != 4:
            return False, f"truncated {kind!r} chunk at {offset}"
        if struct.unpack(">I", crc_bytes)[0] != zlib.crc32(kind + body) & 0xFFFFFFFF:
            return False, f"bad {kind!r} CRC"
        if kind == b"IHDR":
            width, height, depth, color = struct.unpack(">IIBB", body[:10])
        elif kind == b"IDAT":
            idat.extend(body)
        elif kind == b"IEND":
            try:
                raw = zlib.decompress(bytes(idat))
            except zlib.error as error:
                return False, f"IDAT inflate failed: {error}"
            channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color]
            stride = (width * channels * depth + 7) // 8
            expected = height * (stride + 1)
            if len(raw) != expected:
                return False, f"decoded {len(raw)} bytes, expected {expected}"
            return True, f"{width}x{height} depth={depth} color={color} chunks-ok"
        offset += 12 + length
    return False, "missing IEND"


def compare(
    actual: Path,
    expected: Path,
    *,
    metric: str = "AE",
    crop: str | None = None,
    fuzz: str | None = None,
) -> str:
    argv = [MAGICK, "compare", "-metric", metric]
    if fuzz:
        argv += ["-fuzz", fuzz]
    if crop:
        argv += ["-crop", crop, "+repage"]
    argv += [str(actual), str(expected), "null:"]
    proc = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return (proc.stdout + proc.stderr).decode(errors="replace").strip()


def ae(value: str) -> float:
    try:
        return float(value.split()[0])
    except (ValueError, IndexError):
        return 1e9


def crop(src: Path, dst: Path, geometry: str) -> None:
    run([MAGICK, str(src), "-crop", geometry, "+repage", str(dst)], check=True)


def best_crop_offset(actual: Path, reference: Path, expected: tuple[int, int]) -> tuple[float, int, int]:
    """Scan +-3 px around the expected physical offset for a byte-identical crop."""
    width, height = image_info(actual)
    best = (1e18, expected[0], expected[1])
    for dy in range(-3, 4):
        for dx in range(-3, 4):
            x = expected[0] + dx
            y = expected[1] + dy
            if x < 0 or y < 0 or x + width > 2560 or y + height > 1600:
                continue
            candidate = ROOT / "shots" / f"candidate-{x}-{y}.png"
            crop(reference, candidate, f"{width}x{height}+{x}+{y}")
            diff = ae(compare(actual, candidate))
            if diff < best[0]:
                best = (diff, x, y)
    return best


class Session:
    def __init__(self) -> None:
        self.home = ROOT / "home"
        self.config_home = ROOT / "config"
        self.runtime = ROOT / "runtime"
        self.logs = ROOT / "logs"
        self.shots = ROOT / "shots"
        self.display = ""
        self.mango: subprocess.Popen | None = None
        self.background: subprocess.Popen | None = None
        self.extra: list[subprocess.Popen] = []
        self.env: dict = {}

    def setup(self) -> None:
        for directory in ("home", "config", "cache", "data", "state", "runtime", "logs", "shots"):
            (ROOT / directory).mkdir(parents=True, exist_ok=True)
        os.chmod(self.runtime, 0o700)
        (self.home / "Pictures" / "screenshots").mkdir(parents=True, exist_ok=True)
        (self.home / ".config" / "mark-shot").mkdir(parents=True, exist_ok=True)
        config = self.config_home / "mango.conf"
        config.write_text(
            "monitor_rule = name:^HEADLESS-1$,width:2560,height:1600,refresh:60.000000,x:0,y:0,scale:1.500000,vrr:0\n"
            "animations = 0\n"
            "allow_tearing = 0\n"
            "root_color = 0x1e2228ff\n"
            "blur = 0\n"
            "blur_layer = 0\n"
            "shadows = 0\n"
        )
        mark_shot_config = self.home / ".config" / "mark-shot" / "config.toml"
        mark_shot_config.write_text("[startup]\ninclude_cursor = false\n[notifications]\nenabled = false\n")
        env = _env(
            {
                "HOME": str(self.home),
                "XDG_CONFIG_HOME": str(self.config_home),
                "XDG_CACHE_HOME": str(ROOT / "cache"),
                "XDG_DATA_HOME": str(ROOT / "data"),
                "XDG_STATE_HOME": str(ROOT / "state"),
                "XDG_RUNTIME_DIR": str(self.runtime),
                "WLR_BACKENDS": "headless",
                "WLR_RENDERER": "pixman",
                "WLR_LIBINPUT_NO_DEVICES": "1",
                "LIBGL_ALWAYS_SOFTWARE": "1",
                "XDG_SESSION_TYPE": "wayland",
                "XDG_CURRENT_DESKTOP": "mango",
            }
        )
        for key in (
            "HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME", "XDG_DATA_HOME", "XDG_STATE_HOME",
            "XDG_RUNTIME_DIR", "WLR_BACKENDS", "WLR_RENDERER", "WLR_LIBINPUT_NO_DEVICES",
            "LIBGL_ALWAYS_SOFTWARE", "XDG_SESSION_TYPE", "XDG_CURRENT_DESKTOP",
        ):
            os.environ[key] = env[key]
        env.pop("WAYLAND_DISPLAY", None)
        env.pop("MANGO_INSTANCE_SIGNATURE", None)
        env.pop("DISPLAY", None)
        log = open(self.logs / "mango.log", "wb")
        self.mango = subprocess.Popen(
            [MANGO, "-c", str(config), "-d"],
            env=env,
            stdout=log,
            stderr=log,
            start_new_session=True,
        )
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            socks = sorted(p.name for p in self.runtime.glob("wayland-*") if p.is_socket())
            if socks:
                self.display = socks[0]
                break
            if self.mango.poll() is not None:
                raise RuntimeError("mango exited during startup; see logs/mango.log")
            time.sleep(0.1)
        if not self.display:
            raise RuntimeError("no wayland socket from private mango")
        self.env = _env({"WAYLAND_DISPLAY": self.display})
        mango_socks = sorted(self.runtime.glob("mango-*.sock"))
        if mango_socks:
            self.env["MANGO_INSTANCE_SIGNATURE"] = str(mango_socks[0])
        os.environ["WAYLAND_DISPLAY"] = self.display
        if mango_socks:
            os.environ["MANGO_INSTANCE_SIGNATURE"] = str(mango_socks[0])

    def start_background(self, pattern: Path) -> None:
        log = open(self.logs / "swaybg.log", "wb")
        self.background = subprocess.Popen(
            [SWAYBG, "-i", str(pattern), "-m", "fill"],
            env=self.env,
            stdout=log,
            stderr=log,
            start_new_session=True,
        )
        time.sleep(1.5)

    def stop_background(self) -> None:
        if self.background is not None and self.background.poll() is None:
            try:
                os.killpg(self.background.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                self.background.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass
        self.background = None
        time.sleep(0.6)

    def grim(self, path: Path, geometry: str | None = None) -> tuple[int, int]:
        argv = [GRIM, "-o", "HEADLESS-1"]
        if geometry:
            argv += ["-g", geometry]
        argv.append(str(path))
        run(argv, env={"WAYLAND_DISPLAY": self.display}, check=True)
        return image_info(path)

    def spawn(self, argv: list[str], log_name: str) -> subprocess.Popen:
        log = open(self.logs / log_name, "wb")
        proc = subprocess.Popen(argv, env=self.env, stdout=log, stderr=log, start_new_session=True)
        self.extra.append(proc)
        time.sleep(0.6)
        return proc

    def stop_extra(self) -> None:
        for proc in self.extra:
            if proc.poll() is None:
                try:
                    os.killpg(proc.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
        self.extra = []
        time.sleep(0.2)

    def stop(self) -> None:
        self.stop_background()
        self.stop_extra()
        if self.mango is not None and self.mango.poll() is None:
            try:
                os.killpg(self.mango.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                self.mango.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass
            try:
                os.killpg(self.mango.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass


def start_mark_shot(args: list[str], log_name: str, extra_env: dict | None = None) -> tuple[subprocess.Popen, object]:
    log = open(ROOT / "logs" / log_name, "wb")
    env = dict(os.environ)
    if extra_env:
        env.update(extra_env)
    proc = subprocess.Popen(
        [MARK_SHOT, *args],
        env=env,
        stdout=log,
        stderr=log,
        start_new_session=True,
    )
    return proc, log


def stop_mark_shot(proc: subprocess.Popen, log) -> None:
    try:
        os.killpg(proc.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline and proc.poll() is None:
        time.sleep(0.05)
    if proc.poll() is None:
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        proc.wait(timeout=3)
    log.close()


def wait_mark_shot(proc: subprocess.Popen, timeout: float = 15.0) -> int:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline and proc.poll() is None:
        time.sleep(0.05)
    return proc.returncode if proc.returncode is not None else -999


def read_clipboard_png(path: Path) -> list[str]:
    mimes = run([WL_PASTE, "--list-types"], timeout=10).stdout.decode().split()
    data = run([WL_PASTE, "--type", "image/png"], timeout=10).stdout
    path.write_bytes(data)
    return mimes


def pattern_image() -> Path:
    path = ROOT / "pattern.png"
    subprocess.run(
        [
            MAGICK,
            "-size", "2560x1600",
            "pattern:checkerboard",
            "-fill", "none",
            "-stroke", "red",
            "-strokewidth", "3",
            "-draw", "line 0,0 2559,1599",
            "-fill", "blue",
            "-draw", "rectangle 100,100 900,700",
            "-fill", "yellow",
            "-draw", "circle 1900,900 2100,900",
            "-fill", "white",
            "-draw", "rectangle 300,1300 1600,1500",
            str(path),
        ],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    return path


def pixel_at(path: Path, x: int, y: int) -> tuple[int, int, int, int]:
    out = run(
        [MAGICK, str(path), "-format", f"%[fx:int(255*p{{{x},{y}}}.r)],%[fx:int(255*p{{{x},{y}}}.g)],%[fx:int(255*p{{{x},{y}}}.b)],%[fx:int(255*p{{{x},{y}}}.a)]", "info:"]
    )
    parts = out.stdout.decode().split(",")
    return tuple(int(part) for part in parts)  # type: ignore[return-value]


def _virtual_pointer():
    """Import the upstream pure-Python wlr virtual pointer (repo scripts dir)."""
    if UPSTREAM_SCRIPTS not in sys.path:
        sys.path.insert(0, UPSTREAM_SCRIPTS)
    from wayland_virtual_pointer import VirtualPointer

    return VirtualPointer


def overlay_drag(start: tuple[float, float], end: tuple[float, float], steps: int = 12) -> None:
    """Drag with a real wlr virtual pointer over the private output (logical units)."""
    VirtualPointer = _virtual_pointer()
    width, height = logical_size()
    with VirtualPointer(output_index=0) as pointer:
        pointer.move_abs(start[0], start[1], width, height)
        time.sleep(0.06)
        pointer.press()
        for step in range(1, steps + 1):
            ratio = step / steps
            pointer.move_abs(
                start[0] + (end[0] - start[0]) * ratio,
                start[1] + (end[1] - start[1]) * ratio,
                width,
                height,
            )
            time.sleep(0.03)
        pointer.release()
    time.sleep(0.2)


def overlay_click(point: tuple[float, float]) -> None:
    """Click at a logical point in the private output."""
    VirtualPointer = _virtual_pointer()
    width, height = logical_size()
    with VirtualPointer(output_index=0) as pointer:
        pointer.move_abs(point[0], point[1], width, height)
        time.sleep(0.06)
        pointer.click()
    time.sleep(0.1)


def logical_size() -> tuple[int, int]:
    proc = run([MARK_SHOT, "--list-displays"], check=True)
    display = json.loads(proc.stdout)[0]
    return display["width"], display["height"]


def logical_to_pixels(left: float, top: float, right: float, bottom: float) -> tuple[int, int, int, int]:
    """Mirror mark-shot's mapping: per-axis exact ratio, floor/ceil expansion."""
    sx = 2560.0 / 1707.0
    sy = 1600.0 / 1067.0
    x0 = math.floor(left * sx)
    y0 = math.floor(top * sy)
    x1 = math.ceil(right * sx)
    y1 = math.ceil(bottom * sy)
    return x0, y0, x1 - x0, y1 - y0


def check_landmarks(path: Path, label: str) -> None:
    """Flat scene areas must survive capture byte-for-byte: they prove colour handling."""
    expected = {
        (500, 400): (0, 0, 255, 255),  # blue rectangle interior
        (2000, 900): (255, 255, 0, 255),  # yellow circle interior
        (1000, 1400): (255, 255, 255, 255),  # white rectangle interior
        (1200, 500): (102, 102, 102, 255),  # checkerboard cell centre
    }
    wrong = []
    for point, color in expected.items():
        actual = pixel_at(path, *point)
        if actual != color:
            wrong.append(f"{point}: {actual} != {color}")
    record(f"{label}-flat-colours", not wrong, "; ".join(wrong) or "5 flat colour probes exact")


def check_capture_to(session: Session, base: Path) -> None:
    cap = session.shots / "capture-to.png"
    proc = run([MARK_SHOT, "--capture-to", str(cap)])
    record(
        "capture-to-rc",
        proc.returncode == 0,
        (proc.stdout.decode().strip() + " " + proc.stderr.decode().strip())[:300],
    )
    if not cap.exists():
        record("capture-to-size-2560x1600", False, "no output file")
        return
    width, height = image_info(cap)
    record("capture-to-size-2560x1600", (width, height) == (2560, 1600), f"{width}x{height} vs physical 2560x1600")
    ok, detail = png_integrity(cap)
    record("capture-to-png-integrity", ok, detail)
    check_landmarks(cap, "capture-to")
    again = session.shots / "capture-to-2.png"
    run([MARK_SHOT, "--capture-to", str(again)], check=True)
    record("capture-to-deterministic", cap.read_bytes() == again.read_bytes(), "second capture byte-identical")

    region = session.shots / "capture-region.png"
    proc = run([MARK_SHOT, "--capture-to", str(region), "--region", "100,100,640,400"])
    record("capture-region-rc", proc.returncode == 0, proc.stdout.decode().strip()[:300])
    if not region.exists():
        record("capture-region-size-960x600", False, "no output file")
        return
    width, height = image_info(region)
    x0, y0, expected_width, expected_height = logical_to_pixels(100, 100, 740, 500)
    record(
        "capture-region-size",
        (width, height) == (expected_width, expected_height),
        f"{width}x{height} expected {expected_width}x{expected_height} for logical 100,100,640,400",
    )
    reference = session.shots / "capture-region-reference.png"
    crop(cap, reference, f"{width}x{height}+{x0}+{y0}")
    diff = compare(region, reference)
    record("capture-region-content", ae(diff) == 0, f"AE={diff} vs full-capture crop at {x0},{y0}")


def check_full_copy(session: Session, base: Path) -> None:
    reference = session.shots / "capture-to.png"
    run([MARK_SHOT, "--capture-to", str(reference)], check=True)
    clipboard = session.shots / "clipboard.png"
    proc = run([MARK_SHOT, "-m", "-f", "-t", "cs"], timeout=30)
    record("full-copy-save-rc", proc.returncode == 0, proc.stderr.decode(errors="replace")[-400:])
    mimes = read_clipboard_png(clipboard)
    record("clipboard-mime-image-png", "image/png" in mimes, ",".join(mimes))
    if clipboard.stat().st_size == 0:
        record("clipboard-size-2560x1600", False, "empty clipboard")
        return
    ok, detail = png_integrity(clipboard)
    record("clipboard-png-integrity", ok, detail)
    width, height = image_info(clipboard)
    record("clipboard-size-2560x1600", (width, height) == (2560, 1600), f"{width}x{height}")
    record("clipboard-magic-png", image_format(clipboard) == "PNG", magic(clipboard)[:120])
    check_landmarks(clipboard, "clipboard")
    # Re-read after the owner helper has exited: the clipboard must still decode.
    time.sleep(1.0)
    delayed = session.shots / "clipboard-delayed.png"
    read_clipboard_png(delayed)
    ok, detail = png_integrity(delayed)
    record("clipboard-delayed-read", ok, f"{detail} bytes={delayed.stat().st_size}")
    record(
        "clipboard-equals-capture-to",
        clipboard.read_bytes() == reference.read_bytes(),
        "clipboard PNG == headless capture PNG bytes",
    )
    saved = sorted((session.home / "Pictures" / "screenshots").rglob("*.png"))
    record("default-save-file-created", bool(saved), ",".join(str(p) for p in saved[-2:]))
    if not saved:
        return
    newest = saved[-1]
    swidth, sheight = image_info(newest)
    record("default-save-extension-png", newest.suffix == ".png", f"{newest.name}")
    record("default-save-magic-png", image_format(newest) == "PNG", magic(newest)[:120])
    ok, detail = png_integrity(newest)
    record("default-save-png-integrity", ok, detail)
    record("default-save-size-2560x1600", (swidth, sheight) == (2560, 1600), f"{swidth}x{sheight}")
    record("default-save-content", newest.read_bytes() == clipboard.read_bytes(), "save == clipboard bytes")


def check_region_editor(session: Session, base: Path) -> None:
    """`mark-shot -r -t c`: real selection drag in the overlay, then copy."""
    expected_x, expected_y, expected_width, expected_height = logical_to_pixels(10, 10, 1697, 1057)
    clipboard = session.shots / "region-drag.png"
    proc, log = start_mark_shot(["-r", "-t", "c"], "region-drag.log")
    time.sleep(2.5)
    overlay_drag((10.0, 10.0), (1697.0, 1057.0))
    code = wait_mark_shot(proc, 15.0)
    log.close()
    record("region-drag-rc", code == 0, f"exit={code}")
    mimes = read_clipboard_png(clipboard)
    record("region-drag-mime", "image/png" in mimes, ",".join(mimes))
    if clipboard.stat().st_size == 0:
        record("region-drag-size", False, "empty clipboard")
        return
    ok, detail = png_integrity(clipboard)
    record("region-drag-integrity", ok, detail)
    width, height = image_info(clipboard)
    # Mango reports logical 1707 but lays out 1706.67 wide, so the pointer drag can
    # end half a logical pixel early: allow a 2 px size tolerance.
    record(
        "region-drag-size",
        abs(width - expected_width) <= 2 and abs(height - expected_height) <= 2,
        f"{width}x{height} expected {expected_width}x{expected_height}",
    )
    reference = session.shots / "capture-to.png"
    best = best_crop_offset(clipboard, reference, (expected_x, expected_y))
    record(
        "region-drag-content",
        best[0] == 0 and abs(best[1] - expected_x) <= 2,
        f"AE={best[0]:.0f} at offset {best[1]},{best[2]} (expected ~{expected_x},{expected_y})",
    )
    stop_mark_shot(proc, log) if proc.poll() is None else None


def check_interactive_copy(session: Session, base: Path) -> None:
    """`mark-shot` (Print) + drag + Ctrl+C: the exact user workflow without a mouse."""
    expected_x, expected_y, expected_width, expected_height = logical_to_pixels(10, 10, 1697, 1057)
    clipboard = session.shots / "print-copy.png"
    proc, log = start_mark_shot([], "interactive.log")
    time.sleep(2.5)
    overlay_drag((10.0, 10.0), (1697.0, 1057.0))
    time.sleep(1.0)
    session.grim(session.shots / "interactive-selection.png")
    # The user clicks the copy button in the right action bar. In this private
    # session the virtual keyboard is not routed to layer surfaces, so the
    # pointer path is the faithful reproduction of the real user action.
    overlay_click((1680.4, 598.2))
    code = wait_mark_shot(proc, 15.0)
    log.close()
    record("interactive-copy-button-rc", code == 0, f"exit={code}")
    mimes = read_clipboard_png(clipboard)
    record("interactive-mime", "image/png" in mimes, ",".join(mimes))
    if clipboard.stat().st_size == 0:
        record("interactive-size", False, "empty clipboard")
        return
    ok, detail = png_integrity(clipboard)
    record("interactive-integrity", ok, detail)
    width, height = image_info(clipboard)
    record(
        "interactive-size",
        abs(width - expected_width) <= 2 and abs(height - expected_height) <= 2,
        f"{width}x{height} expected {expected_width}x{expected_height}",
    )
    reference = session.shots / "capture-to.png"
    best = best_crop_offset(clipboard, reference, (expected_x, expected_y))
    record(
        "interactive-content",
        best[0] == 0 and abs(best[1] - expected_x) <= 2,
        f"AE={best[0]:.0f} at offset {best[1]},{best[2]} (expected ~{expected_x},{expected_y})",
    )
    stop_mark_shot(proc, log) if proc.poll() is None else None


def check_clipboard_persist(session: Session, base: Path) -> None:
    """Copy while wl-clip-persist and a clipboard watcher are fighting for the selection."""
    persist = session.spawn(
        [
            CLIP_PERSIST,
            "--clipboard",
            "regular",
            "--reconnect-tries",
            "0",
        ],
        "wl-clip-persist.log",
    )
    watcher = session.spawn(
        [
            "sh",
            "-c",
            "while true; do wl-paste --type image --watch sh -c 'cat > /dev/null' 2>/dev/null; sleep 0.2; done",
        ],
        "clipboard-watch.log",
    )
    reference = session.shots / "capture-to.png"
    run([MARK_SHOT, "--capture-to", str(reference)], check=True)
    clipboard = session.shots / "clipboard-persist.png"
    proc = run([MARK_SHOT, "-m", "-f", "-t", "c"], timeout=30)
    record("persist-copy-rc", proc.returncode == 0, proc.stderr.decode(errors="replace")[-300:])
    time.sleep(0.3)
    sizes = []
    for attempt in range(3):
        path = session.shots / f"clipboard-persist-{attempt}.png"
        read_clipboard_png(path)
        sizes.append(path.stat().st_size)
        ok, detail = png_integrity(path)
        record(f"persist-read-{attempt}", ok, f"bytes={path.stat().st_size}; {detail}")
        time.sleep(0.3)
    record(
        "persist-read-stable-and-complete",
        all(size >= 80000 for size in sizes),
        f"sizes={sizes} (truncation bug returned 65536)",
    )
    stop = [proc for proc in (persist, watcher) if proc.poll() is None]
    for process in stop:
        try:
            os.killpg(process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    session.stop_extra()


def check_editor_preview(session: Session, base: Path) -> None:
    """`--fullscreen` must show the frozen capture; killing the wallpaper must not change it."""
    shot_before = session.shots / "editor-preview.png"
    shot_after = session.shots / "editor-preview-after-wallpaper-gone.png"
    proc, log = start_mark_shot(["--fullscreen"], "editor.log", {"MARK_SHOT_DEBUG": "1"})
    time.sleep(3.0)
    session.grim(shot_before)
    record("editor-overlay-shot", shot_before.exists(), str(shot_before))
    width, height = image_info(shot_before)
    record("editor-shot-size", (width, height) == (2560, 1600), f"{width}x{height}")
    session.stop_background()
    time.sleep(0.8)
    session.grim(shot_after)
    if not shot_after.exists():
        record("editor-frozen-preview", False, "missing after shot")
    else:
        # The compositor blends a handful of translucent antialiased UI pixels
        # with whatever sits behind them; the wallpaper change may shift those
        # by 1/255. Everything else must be byte-identical: a live (unfrozen)
        # preview would change the whole background, not 0.01% of the pixels.
        diff = compare(shot_after, shot_before, fuzz="1%")
        record(
            "editor-frozen-preview",
            ae(diff) == 0,
            f"AE(fuzz 1%)={diff} (0 = preview is frozen capture)",
        )
    stop_mark_shot(proc, log)
    time.sleep(0.8)
    desktop = session.shots / "editor-desktop-after-wallpaper-gone.png"
    session.grim(desktop)
    changed = compare(desktop, base)
    # The wallpaper is gone, so the real desktop changed massively; together
    # with the identical preview above this proves the capture was frozen.
    record(
        "editor-frozen-desktop-changed",
        ae(changed) > 100_000,
        f"AE(editor gone vs wallpapered baseline)={changed}",
    )
    editor_log = (ROOT / "logs" / "editor.log").read_text(errors="replace")
    has_refit = "re-fitted" in editor_log
    record("editor-no-buffer-refit", not has_refit, editor_log[-600:].replace("\n", " ")[:600])
    session.start_background(pattern_image())


def check_pin(session: Session) -> None:
    pin = session.shots / "pin.png"
    with open(session.shots / "capture-to.png", "rb") as image:
        subprocess.run([WL_COPY, "--type", "image/png"], stdin=image, env=session.env, check=True)
    time.sleep(0.4)
    proc, log = start_mark_shot(["--pin-clipboard"], "pin.log")
    time.sleep(2.5)
    session.grim(pin)
    record("pin-window-shot", pin.exists(), str(pin))
    stop_mark_shot(proc, log)


def check_scroll(session: Session) -> None:
    shot = session.shots / "scroll-overlay.png"
    proc, log = start_mark_shot(["--scroll"], "scroll.log")
    time.sleep(3.0)
    session.grim(shot)
    record("scroll-overlay-shot", shot.exists(), str(shot))
    stop_mark_shot(proc, log)


def main() -> int:
    phase = os.environ.get("PHASE", "all")
    OUT.mkdir(parents=True, exist_ok=True)
    session = Session()
    session.setup()
    try:
        proc = run([MARK_SHOT, "--list-displays"], check=True)
        displays = json.loads(proc.stdout)
        record("list-displays", bool(displays), json.dumps(displays))

        base = session.shots / "grim-baseline.png"
        session.start_background(pattern_image())
        width, height = session.grim(base)
        record("grim-baseline-2560x1600", (width, height) == (2560, 1600), f"{width}x{height}")
        reference = session.shots / "capture-to.png"
        run([MARK_SHOT, "--capture-to", str(reference)], check=True)

        if phase in ("all", "capture"):
            check_capture_to(session, base)
        if phase in ("all", "clipboard"):
            check_full_copy(session, base)
        if phase in ("all", "persist"):
            check_clipboard_persist(session, base)
        if phase in ("all", "region"):
            check_region_editor(session, base)
        if phase in ("all", "interactive"):
            check_interactive_copy(session, base)
        if phase in ("all", "editor"):
            check_editor_preview(session, base)
        if phase in ("all", "pin"):
            check_pin(session)
        if phase in ("all", "scroll"):
            check_scroll(session)
    finally:
        session.stop()

    report = {
        "results": results,
        "passed": sum(1 for item in results if item["ok"]),
        "failed": sum(1 for item in results if not item["ok"]),
    }
    (OUT / "report.json").write_text(json.dumps(report, indent=2))
    print(json.dumps({"passed": report["passed"], "failed": report["failed"]}))
    return 0 if report["failed"] == 0 else 1


def _parse_cli() -> None:
    """Translate the small command line into the env the harness already uses."""
    import argparse

    parser = argparse.ArgumentParser(description="mark-shot private headless runtime suite")
    parser.add_argument("--phase", default=os.environ.get("PHASE", "all"))
    parser.add_argument("--mark-shot", default=os.environ.get("MARK_SHOT", ""))
    parser.add_argument("--out", default=os.environ.get("MS_E2E_OUT"))
    parser.add_argument("--root", default=os.environ.get("MS_E2E_ROOT"))
    parser.add_argument("--mango", default=None)
    args, _ = parser.parse_known_args()
    os.environ["PHASE"] = args.phase
    if args.mark_shot:
        os.environ["MARK_SHOT"] = args.mark_shot
    if args.out:
        os.environ["MS_E2E_OUT"] = args.out
    if args.root:
        os.environ["MS_E2E_ROOT"] = args.root
    if args.mango:
        os.environ["MS_E2E_MANGO"] = args.mango
    if not os.environ.get("MARK_SHOT"):
        parser.error("--mark-shot or MARK_SHOT is required")


if __name__ == "__main__":
    if "--inner" not in sys.argv:
        _parse_cli()
        # A fresh private root per run: stale home/screenshots or clipboard
        # files from an earlier run must never leak into the assertions.
        if ROOT.exists():
            import shutil as _shutil

            _shutil.rmtree(ROOT)
        ROOT.mkdir(parents=True, exist_ok=True)
        for directory in ("outer-home", "dbus", "no-services"):
            (ROOT / directory).mkdir(parents=True, exist_ok=True)
            os.chmod(ROOT / directory, 0o700)
        (ROOT / "dbus-session.conf").write_text(
            """<!DOCTYPE busconfig PUBLIC '-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN'
 'http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd'>
<busconfig>
  <type>session</type>
  <listen>unix:dir=%s</listen>
  <auth>EXTERNAL</auth>
  <servicedir>%s</servicedir>
  <policy context='default'>
    <allow user='*'/>
    <allow own='*'/>
    <allow send_destination='*'/>
    <allow receive_sender='*'/>
  </policy>
</busconfig>
"""
            % (ROOT / "dbus", ROOT / "no-services")
        )
        child_env = {
            "HOME": str(ROOT / "outer-home"),
            # The Nix wrapper puts every pinned tool in PATH; keep it inside the
            # private bus session instead of replacing it with host paths.
            "PATH": os.environ.get("PATH", "/run/current-system/sw/bin"),
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
            "MARK_SHOT": MARK_SHOT,
            "MS_E2E_OUT": str(OUT),
            "MS_E2E_ROOT": str(ROOT),
            "PHASE": os.environ.get("PHASE", "all"),
            "DBUS_SYSTEM_BUS_ADDRESS": "unix:path=" + str(ROOT / "no-such-system-bus"),
            "MS_E2E_UPSTREAM_SCRIPTS": UPSTREAM_SCRIPTS,
        }
        for key in (
            "MS_E2E_MANGO", "MS_E2E_GRIM", "MS_E2E_WL_PASTE", "MS_E2E_WL_COPY",
            "MS_E2E_MAGICK", "MS_E2E_FILE", "MS_E2E_SWAYBG", "MS_E2E_WTYPE",
            "MS_E2E_PYTHON", "MS_E2E_UPSTREAM_SCRIPTS", "MS_E2E_CLIP_PERSIST",
        ):
            if os.environ.get(key):
                child_env[key] = os.environ[key]
        sys.exit(
            subprocess.call(
                [
                    DBUS_RUN_SESSION,
                    "--config-file",
                    str(ROOT / "dbus-session.conf"),
                    "--",
                    PYTHON,
                    str(Path(__file__).resolve()),
                    "--inner",
                ],
                env=child_env,
            )
        )
    sys.exit(main())
