#!/usr/bin/env python3
"""Check the production dmenu card on a small isolated X server."""

import json
from pathlib import Path
import re
import subprocess
import sys
import time

programs = json.loads(Path(sys.argv[1]).read_text())
output = Path(sys.argv[2])
screen_w, screen_h = map(int, subprocess.check_output(
    [programs['xdotool'], 'getdisplaygeometry'], text=True).split())
subprocess.run([programs['xrdb'], '-merge'], input='Xft.dpi: 144\n', text=True, check=True)


def menu_window(process):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        found = subprocess.run([programs['xdotool'], 'search', '--onlyvisible', '--class', 'dmenu'],
                               capture_output=True, text=True)
        if found.returncode == 0:
            return found.stdout.splitlines()[-1]
        if process.poll() is not None:
            raise AssertionError(process.communicate())
        time.sleep(0.05)
    raise AssertionError('small-screen dmenu did not map')


for cancel in (False, True):
    process = subprocess.Popen([programs['dmenu'], '-p', '应用'], stdin=subprocess.PIPE,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        process.stdin.write(''.join(f'row-{i}\n' for i in range(1, 9)))
        process.stdin.close()
        process.stdin = None
        window = menu_window(process)
        info = subprocess.check_output([programs['xwininfo'], '-id', window], text=True)
        def field(label):
            return int(re.search(r'^\s*' + re.escape(label) + r':\s*(-?\d+)', info, re.MULTILINE)[1])
        x, y = field('Absolute upper-left X'), field('Absolute upper-left Y')
        width, height, border = field('Width'), field('Height'), field('Border width')
        assert 0 <= x and 0 <= y, info
        assert x + width + 2 * border <= screen_w + 2, info
        assert y + height + 2 * border <= screen_h + 2, info
        assert abs(x + (width + 2 * border) / 2 - screen_w / 2) <= 3, info
        assert abs(y + (height + 2 * border) / 2 - screen_h / 2) <= 3, info
        if cancel:
            subprocess.run([programs['xdotool'], 'key', '--clearmodifiers', 'Escape'], check=True)
        else:
            subprocess.run([programs['maim'], str(output / 'small-menu-preview.png')], check=True)
            # The last entry must remain reachable after the visible list shrinks.
            subprocess.run([programs['xdotool'], 'key', '--clearmodifiers', *(['Down'] * 7), 'Return'], check=True)
        stdout, stderr = process.communicate(timeout=5)
        assert process.returncode == (1 if cancel else 0), stderr
        assert stdout == ('' if cancel else 'row-8\n'), repr(stdout)
    finally:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=5)
(output / 'small-menu.txt').write_text('420x260 bounds, centering, scrolling and Escape passed.\n')
