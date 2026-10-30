"""Nested Gamescope preset; discovers physical output modes without changing them."""
import argparse
import json
import os
import re
import subprocess
import sys

GPU_KEYS = ("__NV_PRIME_RENDER_OFFLOAD", "__NV_PRIME_RENDER_OFFLOAD_PROVIDER",
            "__GLX_VENDOR_LIBRARY_NAME", "__VK_LAYER_NV_optimus", "DRI_PRIME")


def compositor_environment(env):
    env = env.copy()
    # Steam/Prism may already have applied game-run. Keep the compositor on
    # its desktop GPU; the actual game receives a fresh offload/Mode request.
    for key in GPU_KEYS:
        env.pop(key, None)
    preloads = [entry for entry in re.split(r"[:\s]+", env.get("LD_PRELOAD", ""))
                if entry and not entry.rsplit("/", 1)[-1].startswith("libgamemodeauto.so")]
    if preloads:
        env["LD_PRELOAD"] = ":".join(preloads)
    else:
        env.pop("LD_PRELOAD", None)
    return env


def query(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True, timeout=3).stdout


def output_mode(name=None):
    if os.environ.get("WAYLAND_DISPLAY"):
        outputs = json.loads(query("wlr-randr", "--json"))
        if not name:
            try:
                name = json.loads(query("mmsg", "get", "cursorpos"))["monitor"]
            except (OSError, ValueError, KeyError, subprocess.SubprocessError):
                pass
        for output in outputs:
            if not output.get("enabled") or (name and name != output["name"]):
                continue
            for mode in output["modes"]:
                if mode.get("current"):
                    return mode["width"], mode["height"], round(mode["refresh"])
    else:
        current = False
        for line in query("xrandr", "--current").splitlines():
            if line and not line[0].isspace():
                current = " connected" in line and (not name or line.split()[0] == name)
            elif current and "*" in line:
                fields = line.split()
                width, height = map(int, fields[0].split("x"))
                refresh = next(rate for rate in fields[1:] if "*" in rate)
                return width, height, round(float(refresh.rstrip("*+")))
    raise ValueError("no current output mode; specify --size WIDTHxHEIGHT --refresh HZ")


def size(value):
    if not re.fullmatch(r"[1-9][0-9]*x[1-9][0-9]*", value):
        raise argparse.ArgumentTypeError("expected WIDTHxHEIGHT")
    return tuple(map(int, value.split("x")))


def positive(value):
    number = int(value)
    if number <= 0:
        raise argparse.ArgumentTypeError("expected a positive integer")
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", help="physical output name; defaults to output under pointer")
    parser.add_argument("--size", type=size, help="output resolution override")
    parser.add_argument("--refresh", type=positive, help="output refresh override in Hz")
    parser.add_argument("--render-size", type=size, help="game resolution, e.g. 1920x1200")
    parser.add_argument("--fps", type=positive, help="frame limit (defaults to output refresh)")
    parser.add_argument("--fsr", action="store_true")
    parser.add_argument("--hdr", action="store_true", help="opt in only on a working HDR output")
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command and command[0] == "--":
        command.pop(0)
    if not command:
        parser.error("a game command after -- is required")
    if args.size and args.refresh:
        width, height = args.size
        refresh = args.refresh
    else:
        width, height, refresh = output_mode(args.output)
        if args.size:
            width, height = args.size
        refresh = args.refresh or refresh
    render_width, render_height = args.render_size or (width, height)
    flags = ["-f", "-W", str(width), "-H", str(height), "-w", str(render_width),
             "-h", str(render_height), "-r", str(args.fps or refresh),
             "--framerate-limit", str(args.fps or refresh)]
    # 3.16.23's automatic SDL backend aborted on child shutdown in the isolated
    # Wayland smoke; its native Wayland backend completed the same run cleanly.
    if os.environ.get("WAYLAND_DISPLAY"):
        flags = ["--backend", "wayland", *flags]
    if args.fsr:
        flags += ["-F", "fsr"]
    if args.hdr:
        flags += ["--hdr-enabled"]
        os.environ["ENABLE_GAMESCOPE_WSI"] = "1"
        os.environ["DXVK_HDR"] = "1"
    os.execvpe("gamescope", ["gamescope", *flags, "--", "game-run", *command],
              compositor_environment(os.environ))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        sys.exit(f"gamescope-run: {error}")
