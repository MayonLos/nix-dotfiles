#!/usr/bin/env python3
"""Verify the production themed Rofi dmenu wrapper on isolated Xvfb."""

import json
from pathlib import Path
import re
import subprocess
import sys
import time

programs = json.loads(Path(sys.argv[1]).read_text())
output = Path(sys.argv[2])
theme = Path(programs["launcherTheme"]).read_text()
assert "border: 0px 0px 0px 3px" in theme and "border-color: @blue" in theme
assert "width: 840px" in theme
assert "-no-custom" in Path(programs["rofiDmenu"]).read_text()
screen_w, screen_h = map(int, subprocess.check_output([programs["xdotool"], "getdisplaygeometry"], text=True).split())
assert (screen_w, screen_h) == (2560, 1600), (screen_w, screen_h)
subprocess.run([programs["xrdb"], "-merge"], input="Xft.dpi: 144\n", text=True, check=True)


def visible_window(process):
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        found = subprocess.run([programs["xdotool"], "search", "--onlyvisible", "--class", "rofi"], capture_output=True, text=True)
        if found.returncode == 0:
            return found.stdout.splitlines()[-1]
        if process.poll() is not None:
            raise AssertionError(f"Rofi exited early: {process.returncode}")
        time.sleep(0.05)
    raise AssertionError("Rofi themed menu did not map")


def field(info, name):
    match = re.search(r"^\s*" + re.escape(name) + r":\s*(-?\d+)", info, re.MULTILINE)
    assert match, (name, info)
    return int(match.group(1))


for choose in (False, True):
    process = subprocess.Popen(
        [programs["rofiDmenu"], "-p", "Fixture", "-lines", "6"],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    try:
        process.stdin.write("".join(f"fixture-{i}\n" for i in range(1, 10)))
        process.stdin.close()
        process.stdin = None
        win = visible_window(process)
        info = subprocess.check_output([programs["xwininfo"], "-id", win], text=True)
        x, y = field(info, "Absolute upper-left X"), field(info, "Absolute upper-left Y")
        width, height, border = field(info, "Width"), field(info, "Height"), field(info, "Border width")
        assert abs(width - 840) < 20, info
        assert 0 <= x and 0 <= y and x + width + 2 * border <= screen_w + 2, info
        assert y + height + 2 * border <= screen_h + 2, info
        assert abs(x + (width + 2 * border) / 2 - screen_w / 2) <= 5, info
        time.sleep(0.5)
        if choose:
            subprocess.run([programs["xdotool"], "key", "--clearmodifiers", *(["Down"] * 8), "Return"], check=True)
        else:
            subprocess.run([programs["imagemagickImport"], "-window", "root", str(output / "rofi-dmenu.png")], check=True, timeout=15)
            subprocess.run([programs["xdotool"], "key", "--clearmodifiers", "Escape"], check=True)
        stdout, stderr = process.communicate(timeout=5)
        assert process.returncode == (0 if choose else 1), stderr
        assert stdout == ("fixture-9\n" if choose else ""), repr(stdout)
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=5)

(output / "rofi-menu-scope.txt").write_text("Production xorg-rofi-dmenu theme, prompt, 560 logical px scaling, bounds, selection, and Escape passed under Xvfb.\n")
