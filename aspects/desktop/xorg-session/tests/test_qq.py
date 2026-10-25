#!/usr/bin/env python3
"""Inspect the produced wrapper and replace only its final QQ exec with a spy."""

import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    spy = root / "qq-spy"
    spy.write_text(f"#!{sys.executable}\nimport json,sys\nprint(json.dumps(sys.argv[1:]))\n")
    spy.chmod(0o700)
    source = Path(sys.argv[1]).read_text()
    source, count = re.subn(r"exec /nix/store/[^\s]+/bin/qq ", f"exec {spy} ", source)
    assert count == 1, "QQ wrapper no longer has the expected single final exec"
    wrapper = root / "qq-launcher"
    wrapper.write_text(source)
    wrapper.chmod(0o700)
    args = ["--user-data-dir", "scratch path 中文", "qq://example?a=one&b=two"]
    for session, wayland, expected in [("wayland", "wayland-1", "wayland"), ("x11", "stale-wayland", "x11"), ("x11", "", "x11")]:
        env = dict(os.environ, XDG_SESSION_TYPE=session, WAYLAND_DISPLAY=wayland)
        result = subprocess.check_output([str(wrapper), *args], text=True, env=env)
        assert json.loads(result) == [f"--ozone-platform={expected}", "--xdg-portal-required-version=3", *args]
        print(f"{session}: backend={expected}, argv preserved")
