#!/usr/bin/env python3
"""End-to-end check for the Nix-built mark-shot in-process media library.

This drives the *packaged* `mark-shot` binary (store path with its
`bin/media/libmarkshot-media.so`) inside a private headless Sway session:

1. verifies the `ms_media_abi` ABI version directly through ctypes;
2. starts a private D-Bus daemon and a headless Sway (`WLR_BACKENDS=headless`,
   pixman, one 1280x720 output);
3. paints a colored fixture on screen with mark-shot's own pinned-image window
   and verifies the pixels are really visible through a real screenshot;
4. opens the real `--record` controller, focuses it, starts recording with a
   wlroots virtual keyboard (Enter), polls `--recording-status` until the
   in-process session is running, stops it with `--stop-recording`, and waits
   for the saved file;
5. validates the saved MP4/GIF with ffprobe (codec, size, duration), a full
   `ffmpeg -xerror` decode, the decoded frame count, and the fixture colors in
   the first decoded frame;
6. captures the recording process under strace (when available) so the log
   shows `bin/media/libmarkshot-media.so` being opened and no GPL FFmpeg
   shared libraries being used.

Every process started here belongs to this script and is stopped on exit; no
user session, display, D-Bus or process is touched.

Example (paths are store paths from the Nix build; see README):
  python3 verify-nix-package.py \
    --mark-shot /nix/store/...-mark-shot-0.2.0/bin/mark-shot \
    --evidence .work/media/evidence/final \
    --sway /nix/store/...-sway-1.12/bin/sway \
    --swaymsg /nix/store/...-sway-1.12/bin/swaymsg \
    --dbus-daemon /nix/store/...-dbus-1.16.2/bin/dbus-daemon \
    --wtype /nix/store/...-wtype-0.4/bin/wtype \
    --grim /nix/store/...-grim-1.5.0/bin/grim \
    --ffmpeg /nix/store/...-ffmpeg-8.1.3-bin/bin/ffmpeg \
    --ffprobe /nix/store/...-ffmpeg-8.1.3-bin/bin/ffprobe \
    --strace /nix/store/...-strace-7.3/bin/strace \
    --foot /nix/store/...-foot-1.27.0/bin/foot \
    --foot-terminfo /nix/store/...-foot-1.27.0-terminfo
"""

import argparse
import json
import math
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

SWAY_CONFIG = """
xwayland disable
output HEADLESS-1 mode 1280x720 position 0 0 scale 1
seat seat0 attach *
default_border none
focus_follows_mouse yes
# Known geometry for the recording setup window. The form starts recording on
# Enter, so the exact position only makes the evidence screenshots readable.
for_window [app_id="mark-shot-recording"] floating enable
for_window [app_id="mark-shot-recording"] resize set 400 300
for_window [app_id="mark-shot-recording"] move position 40 60
"""

# Colored fixture: 320x240 keeps the pinned layer surface clear of the 400x300
# recording setup window, while still being big enough to validate pixels.
FIXTURE_WIDTH = 320
FIXTURE_HEIGHT = 240
FIXTURE_QUADRANTS = [
    ((255, 0, 0), (0, 0, 255)),
    ((0, 220, 0), (255, 220, 0)),
]
COLOR_TOLERANCE = 48
# Bumped by an animating terminal (or the cursor fallback) so the session sees
# real output damage while recording.
FIXTURE_PIXELS_MINIMUM = 5000


def wait_for(read, accept, description, timeout=30.0, interval=0.05):
    """Poll read() until accept() passes; raise with the last value on timeout."""
    deadline = time.monotonic() + timeout
    value = None
    while time.monotonic() < deadline:
        value = read()
        if accept(value):
            return value
        time.sleep(interval)
    raise RuntimeError(f"{description}: last value {value!r}")


def run(command, env, timeout=30, check=True):
    """Run one helper command; with check=True, raise with its output on failure."""
    result = subprocess.run(
        [str(part) for part in command],
        env=env,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    if check and result.returncode != 0:
        raise RuntimeError(
            f"command failed ({result.returncode}): {command}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return result


class Desktop:
    """Own the private D-Bus daemon and headless Sway instance for this check."""

    def __init__(self, root, sway, swaymsg, dbus_daemon):
        self.root = root
        self.sway = sway
        self.swaymsg = swaymsg
        self.dbus_daemon = dbus_daemon
        self.processes = []
        self.runtime = None
        self.environment = {}

    def __enter__(self):
        self.root.mkdir(parents=True, exist_ok=True)
        for name in ("config", "data", "state", "home"):
            (self.root / name).mkdir(exist_ok=True)
        config = self.root / "sway.conf"
        config.write_text(SWAY_CONFIG)
        # Unix socket paths are limited to ~107 bytes, so keep the Wayland
        # runtime directory in /tmp instead of under the evidence tree.
        runtime = Path(tempfile.mkdtemp(prefix="mark-shot-wl-", dir="/tmp"))
        runtime.chmod(0o700)
        self.runtime = runtime
        environment = {
            "PATH": os.environ.get(
                "PATH", "/run/current-system/sw/bin:/usr/bin:/bin"
            )
            + ":/run/current-system/sw/bin",
            "HOME": str(self.root / "home"),
            "XDG_RUNTIME_DIR": str(runtime),
            "XDG_CONFIG_HOME": str(self.root / "config"),
            "XDG_DATA_HOME": str(self.root / "data"),
            "XDG_STATE_HOME": str(self.root / "state"),
        }
        bus = subprocess.Popen(
            [str(self.dbus_daemon), "--session", "--nofork", "--print-address=1"],
            env=environment,
            stdout=subprocess.PIPE,
            stderr=(self.root / "dbus.log").open("w"),
            start_new_session=True,
        )
        self.processes.append(bus)
        address = bus.stdout.readline().decode().strip()
        if not address:
            raise RuntimeError("private D-Bus daemon did not start")
        environment["DBUS_SESSION_BUS_ADDRESS"] = address
        environment.update(
            WLR_BACKENDS="headless",
            WLR_RENDERER="pixman",
            WLR_HEADLESS_OUTPUTS="1",
        )
        sway = subprocess.Popen(
            [str(self.sway), "-c", str(config)],
            env=environment,
            stdout=subprocess.DEVNULL,
            stderr=(self.root / "sway.log").open("w"),
            start_new_session=True,
        )
        self.processes.append(sway)
        for _ in range(200):
            sockets = list(runtime.glob(f"sway-ipc.{os.getuid()}.*.sock"))
            wayland = [path for path in runtime.glob("wayland-*") if path.is_socket()]
            if len(sockets) == 1 and len(wayland) == 1:
                environment["SWAYSOCK"] = str(sockets[0])
                environment["WAYLAND_DISPLAY"] = wayland[0].name
                break
            if sway.poll() is not None:
                raise RuntimeError(f"headless sway exited: see {self.root / 'sway.log'}")
            time.sleep(0.03)
        else:
            raise RuntimeError("headless sway sockets did not appear")
        self.environment = environment
        outputs = json.loads(run([self.swaymsg, "-t", "get_outputs"], environment).stdout)
        geometry = {
            item["name"]: (item["current_mode"]["width"], item["current_mode"]["height"])
            for item in outputs
        }
        if geometry != {"HEADLESS-1": (1280, 720)}:
            raise RuntimeError(f"unexpected headless outputs: {geometry}")
        return self

    def tree(self):
        return json.loads(run([self.swaymsg, "-t", "get_tree"], self.environment).stdout)

    def windows(self, app_id):
        found = []

        def walk(node):
            if node.get("app_id") == app_id and node.get("pid"):
                found.append(node)
            for child in node.get("nodes", []) + node.get("floating_nodes", []):
                walk(child)

        walk(self.tree())
        return found

    def command(self, command):
        run([self.swaymsg, *command.split()], self.environment)

    def __exit__(self, *_arguments):
        for process in reversed(self.processes):
            if process.poll() is not None:
                continue
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except (ProcessLookupError, PermissionError):
                process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(process.pid, signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    process.kill()
                process.wait(timeout=5)
        if self.runtime:
            shutil.rmtree(self.runtime, ignore_errors=True)


def write_fixture(path):
    """Write the PPM fixture without depending on an image library."""
    cell_w, cell_h = FIXTURE_WIDTH // 2, FIXTURE_HEIGHT // 2
    with path.open("wb") as stream:
        stream.write(b"P6\n%d %d\n255\n" % (FIXTURE_WIDTH, FIXTURE_HEIGHT))
        for y in range(FIXTURE_HEIGHT):
            palette = FIXTURE_QUADRANTS[1 if y >= cell_h else 0]
            row = bytearray()
            for x in range(FIXTURE_WIDTH):
                row.extend(palette[1 if x >= cell_w else 0])
            stream.write(row)


def fixture_colors():
    return [color for pair in FIXTURE_QUADRANTS for color in pair]


def count_fixture_pixels(pixels):
    matched = 0
    for offset in range(0, len(pixels), 3):
        r, g, b = pixels[offset], pixels[offset + 1], pixels[offset + 2]
        for color in fixture_colors():
            if (
                abs(r - color[0]) < COLOR_TOLERANCE
                and abs(g - color[1]) < COLOR_TOLERANCE
                and abs(b - color[2]) < COLOR_TOLERANCE
            ):
                matched += 1
                break
    return matched


def decode_single_frame(ffmpeg, path):
    """Decode the first video frame to packed RGB24 bytes."""
    raw = subprocess.run(
        [
            str(ffmpeg),
            "-v",
            "error",
            "-i",
            str(path),
            "-frames:v",
            "1",
            "-pix_fmt",
            "rgb24",
            "-f",
            "rawvideo",
            "-",
        ],
        capture_output=True,
        timeout=60,
    )
    if raw.returncode != 0:
        raise RuntimeError(f"decoding {path} failed: {raw.stderr.decode()}")
    return raw.stdout


def probe(ffprobe, path):
    return json.loads(
        run(
            [
                ffprobe,
                "-v",
                "error",
                "-show_format",
                "-show_streams",
                "-of",
                "json",
                str(path),
            ],
            os.environ,
        ).stdout
    )


def verify_media(tools, path, expected_codec):
    """Validate container, codec, dimensions, frames, full decode and pixels."""
    report = probe(tools["ffprobe"], path)
    video = next(
        (stream for stream in report["streams"] if stream["codec_type"] == "video"),
        None,
    )
    if video is None:
        raise RuntimeError(f"{path}: no video stream: {report}")
    if video["codec_name"] != expected_codec:
        raise RuntimeError(f"{path}: expected {expected_codec}, got {video['codec_name']}")
    width, height = int(video["width"]), int(video["height"])
    if (width, height) != (1280, 720):
        raise RuntimeError(f"{path}: unexpected dimensions: {width}x{height}")
    duration = float(report["format"]["duration"])
    if duration < 1.0:
        raise RuntimeError(f"{path}: recording too short: {duration}s")
    # -xerror makes any demux/decode error fatal.
    run(
        [
            tools["ffmpeg"],
            "-v",
            "error",
            "-xerror",
            "-i",
            str(path),
            "-enc_time_base",
            "demux",
            "-fps_mode",
            "passthrough",
            "-f",
            "null",
            "-",
        ],
        os.environ,
        timeout=120,
    )
    frames = int(
        json.loads(
            run(
                [
                    tools["ffprobe"],
                    "-v",
                    "error",
                    "-select_streams",
                    "v:0",
                    "-count_frames",
                    "-show_entries",
                    "stream=nb_read_frames",
                    "-of",
                    "json",
                    str(path),
                ],
                os.environ,
            ).stdout
        )["streams"][0]["nb_read_frames"]
    )
    if frames < 8:
        raise RuntimeError(f"{path}: only {frames} decoded frames")
    pixels = decode_single_frame(tools["ffmpeg"], path)
    if len(pixels) != width * height * 3:
        raise RuntimeError(f"{path}: first frame size mismatch: {len(pixels)}")
    matched = count_fixture_pixels(pixels)
    if matched < FIXTURE_PIXELS_MINIMUM:
        raise RuntimeError(f"{path}: fixture colors missing in first frame: {matched}")
    return {
        "duration": duration,
        "frames": frames,
        "codec": video["codec_name"],
        "size": [width, height],
        "fixture_pixels": matched,
        "probe": report,
    }


def record(tools, desktop, root, evidence, name, fmt):
    """Run one real GUI-driven recording and return its verified evidence."""
    target_format = "gif" if fmt == "gif" else "video"
    directory = root / f"videos-{name}"
    directory.mkdir()
    config = root / f"app-{name}.toml"
    config.write_text(
        "[desktop]\n"
        "tray_enabled=false\n"
        "shortcuts_enabled=false\n"
        "[history]\n"
        "enabled=false\n"
        '[ui]\nlanguage="en"\n'
        "[startup]\nselection_loupe=false\n"
        "[recording]\n"
        'encoder="software"\n'
        'audio="off"\n'
        "fps=15\n"
        "gif_fps=12\n"
        "countdown=0\n"
        'quality="balanced"\n'
        f'directory="{directory}"\n'
    )
    environment = dict(desktop.environment, MARK_SHOT_LOG="info")
    log = (root / f"record-{name}.log").open("w")
    command = [
        tools["mark-shot"],
        "--config",
        str(config),
        "--record",
        "--record-target",
        json.dumps({"display": "", "crop": None, "format": target_format}),
    ]
    if tools.get("strace"):
        command = [
            tools["strace"],
            "-f",
            "-o",
            str(evidence / f"strace-{name}.log"),
            "-e",
            "trace=openat,openat2",
            "--",
        ] + command
    process = subprocess.Popen(
        command,
        env=environment,
        stdout=log,
        stderr=log,
        start_new_session=True,
    )
    try:
        wait_for(
            lambda: desktop.windows("mark-shot-recording"),
            bool,
            f"{name}: recording setup window did not open",
        )
        (evidence / f"tree-{name}.json").write_text(
            json.dumps(desktop.tree(), indent=2) + "\n"
        )
        run(
            [tools["grim"], "-o", "HEADLESS-1", str(evidence / f"setup-{name}.png")],
            environment,
        )
        desktop.command('[app_id="mark-shot-recording"] focus')
        # Headless sway has no input devices, so the setup window cannot be
        # clicked through the seat. wtype creates a wlroots virtual keyboard;
        # keep it connected for a moment so the client can bind the new
        # keyboard capability before Enter is delivered. The form starts on
        # Enter.
        run([tools["wtype"], "-s", "800", "-k", "Return"], environment, timeout=30)

        def status():
            result = run(
                [tools["mark-shot"], "--config", str(config), "--recording-status"],
                environment,
                check=False,
            )
            if result.returncode != 0:
                return None
            try:
                return json.loads(result.stdout)
            except json.JSONDecodeError:
                return None

        wait_for(
            status,
            lambda value: value is not None
            and value.get("phase") in ("countdown", "starting", "recording"),
            f"{name}: recording did not start after Enter",
        )
        recording = wait_for(
            status,
            lambda value: value is not None and value.get("phase") == "recording",
            f"{name}: never reached the recording phase",
        )
        time.sleep(2.2)
        run(
            [tools["mark-shot"], "--config", str(config), "--stop-recording"],
            environment,
        )
        finished = wait_for(
            status,
            lambda value: value is not None
            and value.get("phase") in ("finished", "failed"),
            f"{name}: recording did not finish",
            timeout=120,
        )
        (evidence / f"status-{name}.json").write_text(json.dumps(finished, indent=2) + "\n")
        if finished["phase"] != "finished":
            raise RuntimeError(f"{name}: recording failed: {finished}")
        output = Path(finished["output"])
        if not output.is_file() or output.stat().st_size <= 1000:
            raise RuntimeError(f"{name}: missing or empty output: {output}")
        expected_codec = "gif" if fmt == "gif" else "h264"
        result = verify_media(tools, output, expected_codec)
        result.update(
            format=fmt,
            output=str(output),
            bytes=output.stat().st_size,
            encoder=recording.get("detail", ""),
            status=finished,
        )
        (evidence / f"probe-{name}.json").write_text(
            json.dumps(result["probe"], indent=2) + "\n"
        )
        return result
    finally:
        if process.poll() is None:
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=5)
        log.close()


def load_abi(media):
    """Dlopen the shared object exactly like a consumer and return ms_media_abi."""
    import ctypes

    library = ctypes.CDLL(str(media))
    library.ms_media_abi.restype = ctypes.c_uint32
    return int(library.ms_media_abi())


def tool(name, candidates):
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return Path(candidate)
    raise SystemExit(f"missing tool: {name}")


def main():
    parser = argparse.ArgumentParser(
        description="End-to-end check for the Nix-built mark-shot media library"
    )
    parser.add_argument("--mark-shot", type=Path, required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--formats", default="mp4,gif")
    parser.add_argument("--sway", type=Path)
    parser.add_argument("--swaymsg", type=Path)
    parser.add_argument("--dbus-daemon", type=Path)
    parser.add_argument("--wtype", type=Path)
    parser.add_argument("--grim", type=Path)
    parser.add_argument("--ffmpeg", type=Path)
    parser.add_argument("--ffprobe", type=Path)
    parser.add_argument("--strace", type=Path)
    parser.add_argument("--foot", type=Path)
    parser.add_argument("--foot-terminfo", type=Path)
    args = parser.parse_args()

    def which(name):
        found = shutil.which(name)
        return Path(found) if found else None

    tools = {
        "mark-shot": args.mark_shot.resolve(),
        "sway": tool("sway", [args.sway, which("sway")]),
        "swaymsg": tool("swaymsg", [args.swaymsg, which("swaymsg")]),
        "dbus-daemon": tool("dbus-daemon", [args.dbus_daemon, which("dbus-daemon")]),
        "wtype": tool("wtype", [args.wtype, which("wtype")]),
        "grim": tool("grim", [args.grim, which("grim")]),
        "ffmpeg": tool("ffmpeg", [args.ffmpeg, which("ffmpeg")]),
        "ffprobe": tool("ffprobe", [args.ffprobe, which("ffprobe")]),
        "strace": args.strace if args.strace else which("strace"),
        "foot": args.foot if args.foot else which("foot"),
        "foot-terminfo": args.foot_terminfo,
    }
    package = tools["mark-shot"].parent.parent
    media = package / "bin" / "media" / "libmarkshot-media.so"
    if not media.is_file():
        raise SystemExit(f"media library is not beside the executable: {media}")
    evidence = args.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    abi = load_abi(media)
    if abi != 2:
        raise SystemExit(f"unexpected media ABI: {abi}")
    fixture = evidence / "fixture.ppm"
    write_fixture(fixture)
    formats = [value.strip() for value in args.formats.split(",") if value.strip()]
    root = Path(tempfile.mkdtemp(prefix="mark-shot-media-e2e-", dir=str(evidence)))
    result = {
        "mark_shot": str(tools["mark-shot"]),
        "media_library": str(media),
        "media_abi": abi,
        "formats": {},
    }
    with Desktop(
        root / "desktop", tools["sway"], tools["swaymsg"], tools["dbus-daemon"]
    ) as desktop:
        environment = desktop.environment
        pin_toml = evidence / "pin.toml"
        pin_toml.write_text(
            "[desktop]\ntray_enabled=false\nshortcuts_enabled=false\n"
            "[history]\nenabled=false\n"
            '[ui]\nlanguage="en"\n'
        )
        pin_log = (root / "pin.log").open("w")
        pin = subprocess.Popen(
            [
                tools["mark-shot"],
                "--config",
                str(pin_toml),
                "--pin-image",
                str(fixture),
            ],
            env=dict(environment, MARK_SHOT_LOG="info"),
            stdout=pin_log,
            stderr=pin_log,
            start_new_session=True,
        )
        animated = None
        animated_log = None
        try:
            # Pinned images use a wlr-layer-shell top surface when available,
            # so they are not listed in sway's tree; verify the fixture is
            # really on screen by screenshotting and decoding the pixels.
            if pin.poll() is not None:
                raise RuntimeError("pinned fixture process exited")
            time.sleep(1.2)
            preview = evidence / "preview.png"
            run([tools["grim"], "-o", "HEADLESS-1", str(preview)], environment)
            fixture_pixels = count_fixture_pixels(decode_single_frame(tools["ffmpeg"], preview))
            if fixture_pixels < FIXTURE_PIXELS_MINIMUM:
                raise RuntimeError(f"fixture colors are not on screen: {fixture_pixels}")
            result["preview_fixture_pixels"] = fixture_pixels

            # mark-shot throttles unchanged output to roughly one encoded frame
            # per second, so keep a real Wayland client animating: a scrolling
            # terminal in a tiled foot window. This is genuine compositor
            # damage, not synthetic frames.
            if tools["foot"] and tools["foot-terminfo"]:
                animated_log = (root / "foot.log").open("w")
                animated = subprocess.Popen(
                    [
                        str(tools["foot"]),
                        "-e",
                        "/run/current-system/sw/bin/sh",
                        "-c",
                        "while :; do date +%s%N; sleep 0.03; done",
                    ],
                    env=dict(
                        environment,
                        TERM="xterm-256color",
                        TERMINFO_DIRS=str(tools["foot-terminfo"] / "share" / "terminfo"),
                    ),
                    stdout=animated_log,
                    stderr=animated_log,
                    start_new_session=True,
                )
                wait_for(
                    lambda: desktop.windows("foot"),
                    bool,
                    "animating terminal did not open",
                    timeout=20,
                )
                time.sleep(0.8)
            for fmt in formats:
                result["formats"][fmt] = record(tools, desktop, root, evidence, fmt, fmt)
        finally:
            for process in (pin, animated):
                if process is not None and process.poll() is None:
                    try:
                        os.killpg(process.pid, signal.SIGTERM)
                    except ProcessLookupError:
                        pass
            for process in (pin, animated):
                if process is None:
                    continue
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=5)
            pin_log.close()
            if animated_log is not None:
                animated_log.close()
    (evidence / "result.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
