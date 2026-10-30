#!/usr/bin/env python3
"""Private-HOME mock integration checks; never captures pixels or sound."""
import json
import os
from pathlib import Path
import sqlite3
import subprocess as sp
import sys
import tempfile
import time

binary = str(Path(sys.argv[1]).resolve())
with tempfile.TemporaryDirectory(prefix="shots-runtime-") as tmp:
    root = Path(tmp)
    home = root / "home"
    home.mkdir()
    stubs = root / "bin"
    stubs.mkdir()
    env = {"HOME": str(home), "PATH": str(stubs) + ":" + os.environ["PATH"],
           "LANG": "C.UTF-8", "XDG_CONFIG_HOME": str(home / ".config"),
           "XDG_DATA_HOME": str(home / ".local/share")}
    stub = f"#!{sys.executable}\n" + '''
import os, pathlib, sys, time
home=pathlib.Path(os.environ["HOME"])
name=pathlib.Path(sys.argv[0]).name
a=sys.argv[1:]
if name=="tesseract":
    if "bad" in a[0]: sys.exit(1)
    if "slow" in a[0]:
        (home/"ocr-running").write_text(str(os.getpid()))
        time.sleep(30)
    print("SYNTHETIC OCR 可搜索")
'''
    for name in ["tesseract"]:
        f = stubs / name
        f.write_text(stub)
        f.chmod(0o755)

    def run(*args, check=True):
        return sp.run([binary, *args], env=env, capture_output=True, text=True, check=check, timeout=45)

    help_text = run("--help").stdout.lower()
    assert "record" not in help_text and "recording" not in help_text
    assert run("search", "x", "--kind", "video", check=False).returncode != 0

    def alive(pid):
        try:
            os.kill(pid, 0)
            return True
        except ProcessLookupError:
            return False

    dbpath = home / ".local/share/shots-mayon/library.sqlite3"


    # Bad oldest image does not poison subsequent local OCR. Files are synthetic.
    images = home / "Pictures/mark-shot"
    images.mkdir(parents=True)
    for i, name in enumerate(["bad.png", "good.png"]):
        f = images / name
        f.write_bytes(b"synthetic image fixture")
        os.utime(f, (1000000000 + i, 1000000000 + i))
    run("index", "--no-ocr")
    assert dbpath.stat().st_mode & 0o777 == 0o600
    assert dbpath.parent.stat().st_mode & 0o777 == 0o700
    run("ocr", "run")
    assert len(json.loads(run("search", "可搜索").stdout)) == 1
    db = sqlite3.connect(dbpath)
    assert db.execute("select ocr_retry_after from entries where name='bad.png'").fetchone()[0] > time.time()
    # While OCR is processing, pause must kill only its own private process group.
    (images / "slow.png").write_bytes(b"synthetic slow fixture")
    run("index", "--no-ocr")
    worker = sp.Popen([binary, "ocr", "run"], env=env, stdout=sp.DEVNULL, stderr=sp.DEVNULL)
    try:
        deadline = time.monotonic() + 5
        while not (home / "ocr-running").exists() and time.monotonic() < deadline:
            time.sleep(.05)
        assert (home / "ocr-running").exists()
        ocr_pid = int((home / "ocr-running").read_text())
        run("ocr", "pause")
        worker.wait(timeout=5)
        assert not alive(ocr_pid), "paused OCR process survived"
    finally:
        if worker.poll() is None:
            worker.terminate()
            worker.wait(timeout=5)
    db.close()
    print("mock runtime: screenshot OCR retry/pause and private permissions PASS")
