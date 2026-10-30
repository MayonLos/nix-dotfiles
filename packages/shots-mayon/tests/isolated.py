#!/usr/bin/env python3
"""Synthetic-only real Kitty/headless sway validation. No inherited session env.

Run with absolute binaries supplied through --path. Artifacts persist under --root.
Never points at the caller's HOME, Wayland or D-Bus. No sound is requested.
"""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess as sp
import time


def wait_for(test, seconds=20):
    until = time.monotonic() + seconds
    while time.monotonic() < until:
        result = test()
        if result:
            return result
        time.sleep(0.1)
    raise TimeoutError("private compositor/application did not become ready")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--binary", required=True)
    p.add_argument("--root", required=True)
    p.add_argument("--path", required=True)
    args = p.parse_args()
    root = Path(args.root).resolve()
    root.mkdir(parents=True, exist_ok=True)
    home = root / "home"
    runtime = root / "rt"
    home.mkdir(exist_ok=True)
    runtime.mkdir(mode=0o700, exist_ok=True)
    runtime.chmod(0o700)
    images = home / "Pictures/mark-shot"
    images.mkdir(parents=True, exist_ok=True)
    env = {
        "HOME": str(home), "XDG_RUNTIME_DIR": str(runtime),
        "XDG_DATA_HOME": str(home / ".local/share"),
        "XDG_CONFIG_HOME": str(home / ".config"),
        "XDG_CACHE_HOME": str(home / ".cache"),
        "PATH": args.path, "LANG": "C.UTF-8", "LC_ALL": "C.UTF-8",
        "TZ": "Asia/Shanghai", "WLR_BACKENDS": "headless",
        "WLR_HEADLESS_OUTPUTS": "1", "WLR_LIBINPUT_NO_DEVICES": "1",
        "WLR_RENDERER": "pixman", "LIBGL_ALWAYS_SOFTWARE": "1",
        "XDG_CURRENT_DESKTOP": "sway", "XDG_SESSION_TYPE": "wayland",
    }
    def run(*cmd, **kw):
        return sp.run(cmd, env=env, check=True, capture_output=True, timeout=60, **kw)
    # All pixels and all text in these fixtures are generated here.
    run("magick", "-size", "1100x700", "xc:#1e2228", "-fill", "#abb2bf",
        "-font", "DejaVu-Sans", "-pointsize", "48", "-annotate", "+55+110",
        "SYNTHETIC CAPTURE\nPRIVATE TEST ONLY\nMango OCR library 2026",
        str(images / "synthetic-terminal.png"))
    run("magick", "-size", "1000x640", "xc:#181b20", "-fill", "#98c379",
        "-draw", "roundrectangle 60,60 930,550 8,8", "-fill", "#1e2228",
        "-font", "DejaVu-Sans", "-pointsize", "42", "-annotate", "+95+150",
        "SYNTHETIC NOTES\nScreenshot archive\nFavorite / timeline",
        str(images / "synthetic-notes.png"))
    for i, src in enumerate(["kitty · synthetic shell", "browser · synthetic notes"]):
        filename = ["synthetic-terminal.png", "synthetic-notes.png"][i]
        image = images / filename
        Path(str(image) + ".shots.json").write_text(json.dumps({"source": src}))
        stamp = 1793322000 - i * 86400
        os.utime(image, (stamp, stamp))
    run(args.binary, "index", "--no-ocr")
    run(args.binary, "ocr", "run")
    search = json.loads(run(args.binary, "search", "SYNTHETIC").stdout)
    assert len(search) == 2, search
    (root / "ocr-search.json").write_text(json.dumps(search, indent=2))
    # Private D-Bus; address never comes from the caller's desktop.
    dbus = run("dbus-daemon", "--session", "--fork", "--print-address=1", "--print-pid=1").stdout.decode().splitlines()
    env["DBUS_SESSION_BUS_ADDRESS"] = dbus[0]
    dbus_pid = int(dbus[1])
    config = root / "sway.conf"
    config.write_text("output * mode 2560x1600 scale 1.5\nfont monospace 10\n"
                      "seat seat0 fallback true\ndefault_border pixel 1\n"
                      "for_window [app_id=shots-verify] floating enable, resize set 1450 930, move position center\n")
    sway_log = (root / "sway.log").open("w")
    kitty_log = (root / "kitty.log").open("w")
    sway = sp.Popen(["sway", "-c", str(config)], env=env, stdout=sway_log, stderr=sp.STDOUT, start_new_session=True)
    kitty = None
    try:
        wayland = wait_for(lambda: next((x for x in runtime.glob("wayland-*") if x.is_socket()), None))
        ipc = wait_for(lambda: next(runtime.glob("sway-ipc.*.sock"), None))
        env["WAYLAND_DISPLAY"] = wayland.name
        env["SWAYSOCK"] = str(ipc)
        remote = root / "kitty.sock"
        kitty = sp.Popen(["kitty", "--config", "NONE", "--class", "shots-verify",
            "--listen-on", "unix:" + str(remote), "-o", "allow_remote_control=yes",
            "-o", "font_family=JetBrainsMono Nerd Font", "-o", "font_size=10.5",
            "-o", "background=#1e2228", "-o", "foreground=#abb2bf",
            "-o", "window_padding_width=8", args.binary], env=env,
            stdout=kitty_log, stderr=sp.STDOUT, start_new_session=True)
        wait_for(remote.exists)
        time.sleep(3)
        def key(*keys):
            run("kitty", "@", "--to", "unix:" + str(remote), "send-key", *keys)
            time.sleep(0.5)
        def shot(name):
            time.sleep(1)
            run("grim", "-o", "HEADLESS-1", str(root / name))
        # Iteration 1: full and narrow layout, then modal checks.
        shot("round1-library.png")
        run("kitty", "@", "--to", "unix:" + str(remote), "send-text", "?")
        time.sleep(0.5)
        shot("round1-help.png")
        key("Escape")
        run("kitty", "@", "--to", "unix:" + str(remote), "resize-os-window", "--width", "90", "--height", "42", "--unit", "cells")
        (root / "narrow-grid.txt").write_bytes(run("kitty", "@", "--to", "unix:" + str(remote), "get-text").stdout)
        run("swaymsg", "[app_id=shots-verify] move position center")
        shot("round1-narrow.png")
        # Round 2 repeats after reviewing the first artifacts; -- reruns overwrite
        # with new code, ensuring screenshots always represent the tested binary.
        run("swaymsg", "[app_id=shots-verify] resize set 1450 930, move position center")
        key("2")
        shot("round2-library.png")
        key("d")
        shot("round2-delete-first.png")
        key("Return")
        shot("round2-delete-second.png")
        key("Escape")
        key("r")
        shot("round2-record-dialog.png")
        key("Escape")
        # Isolated, silent recording only. No microphone/speaker daemon exists.
        first = run(args.binary, "record", "toggle", "--output", "HEADLESS-1").stdout.decode()
        time.sleep(2)
        status = run(args.binary, "record", "status").stdout.decode()
        stopped = run(args.binary, "record", "toggle").stdout.decode()
        files = list((home / "Videos/Recordings").glob("*.mkv"))
        assert len(files) == 1
        probe = json.loads(run("ffprobe", "-v", "error", "-show_streams", "-show_format", "-of", "json", str(files[0])).stdout)
        assert any(s["codec_type"] == "video" for s in probe["streams"])
        assert not any(s["codec_type"] == "audio" for s in probe["streams"])
        assert float(probe["format"]["duration"]) > 0
        (root / "record-verification.json").write_text(json.dumps({"start": first,"status":status,"stop": stopped,"ffprobe": probe},indent=2))
        key("3")
        time.sleep(3)
        shot("round2-recording-library.png")
        key("q")
        kitty.wait(timeout=10)
    finally:
        if kitty and kitty.poll() is None:
            os.killpg(kitty.pid, signal.SIGTERM)
            kitty.wait(timeout=10)
        if sway.poll() is None:
            os.killpg(sway.pid, signal.SIGTERM)
            sway.wait(timeout=10)
        os.kill(dbus_pid, signal.SIGTERM)
        sway_log.close()
        kitty_log.close()
    shots = sorted(root.glob("round*.png"))
    (root / "gallery.html").write_text("<!doctype html><meta charset=utf-8><title>Shots · isolated Kitty verification</title>"
        "<style>body{background:#1e2228;color:#abb2bf;font-family:sans-serif}img{width:98%;border:1px solid #5c6370}</style>"
        "<h1>合成素材 · 私有 HOME · Headless sway · 2560×1600 / scale 1.5</h1>"
        + "".join(f"<h2>{f.name}</h2><img src='{f.name}'>" for f in shots))
    run("magick", "montage", *map(str,shots), "-thumbnail", "640x400", "-tile", "2x", "-geometry", "+8+8", "-background", "#1e2228", str(root / "overview.png"))
    print(root / "gallery.html")


if __name__ == "__main__":
    main()
