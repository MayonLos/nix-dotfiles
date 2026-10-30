#!/usr/bin/env python3
"""Private-HOME mock integration checks; never captures pixels or sound."""
import json
import os
from pathlib import Path
import signal
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
import json, os, pathlib, signal, sys, time
home=pathlib.Path(os.environ["HOME"])
name=pathlib.Path(sys.argv[0]).name
with (home/"calls.jsonl").open("a") as f:
    f.write(json.dumps([name]+sys.argv[1:])+"\\n")
a=sys.argv[1:]
if name=="mmsg":
    if a[-1]=="all-clients":
        print(json.dumps({"clients":[{"appid":"synthetic.kitty","title":"PRIVATE TEST","monitor":"TEST-1","is_visible":True,"is_minimized":False,"x":-1200,"y":24,"width":800,"height":600}]}))
    else: print('{"monitor":"TEST-1"}')
elif name=="slurp": print("-1200,24 800x600")
elif name=="notify-send":
    if (home/"slow-notify").exists(): time.sleep(4)
elif name=="pactl":
    if a[0]=="get-default-sink": print("synthetic-speakers")
    elif a[0]=="get-default-source": print("synthetic-mic")
    elif a[0]=="load-module":
        counter=home/"counter"
        n=int(counter.read_text())+1 if counter.exists() else 1
        counter.write_text(str(n)); print(n)
elif name=="tesseract":
    if "bad" in a[0]: sys.exit(1)
    if "slow" in a[0]:
        (home/"ocr-running").write_text(str(os.getpid()))
        time.sleep(30)
    print("SYNTHETIC OCR 可搜索")
elif name=="wf-recorder":
    (home/"encoder.pid").write_text(str(os.getpid()))
    if (home/"fail-encoder").exists(): sys.exit(1)
    pathlib.Path(a[a.index("-f")+1]).write_bytes(b"synthetic recorder fixture")
    def stop(*args): sys.exit(0)
    signal.signal(signal.SIGINT,stop)
    signal.signal(signal.SIGTERM,stop)
    while True: time.sleep(.05)
'''
    for name in ["wf-recorder", "mmsg", "slurp", "pactl", "notify-send", "tesseract"]:
        f = stubs / name
        f.write_text(stub)
        f.chmod(0o755)

    def run(*args, check=True):
        return sp.run([binary, *args], env=env, capture_output=True, text=True, check=check, timeout=45)

    def alive(pid):
        try:
            os.kill(pid, 0)
            return True
        except ProcessLookupError:
            return False

    def calls():
        return [json.loads(s) for s in (home / "calls.jsonl").read_text().splitlines()]

    # Window source uses Mango's actual 'appid' field; coordinate argv is literal.
    run("record", "toggle", "--window", "--system-audio", "--mic")
    assert "正在录制" in run("record", "status").stdout
    run("record", "toggle")
    pid = int((home / "encoder.pid").read_text())
    assert not alive(pid), "encoder left running after stop"
    recorder = next(c for c in calls() if c[0] == "wf-recorder")
    assert "-1200,24 800x600" in recorder
    assert any(c.startswith("--audio=shots_mayon_") for c in recorder)
    mods = [c for c in calls() if c[:2] == ["pactl", "unload-module"]]
    assert [c[-1] for c in mods] == ["3", "2", "1"], mods
    assert not any("set-default" in c for call in calls() for c in call)
    indexed = json.loads(run("search", "synthetic.kitty", "--kind", "video").stdout)
    assert len(indexed) == 1 and indexed[0]["source"].startswith("synthetic.kitty")
    dbpath = home / ".local/share/shots-mayon/library.sqlite3"
    assert dbpath.stat().st_mode & 0o777 == 0o600
    assert dbpath.parent.stat().st_mode & 0o777 == 0o700

    # Slow notifications are bounded and do not orphan a recording.
    (home / "slow-notify").touch()
    run("record", "toggle", "--region")
    run("record", "toggle")
    assert not alive(int((home / "encoder.pid").read_text()))
    (home / "slow-notify").unlink()
    (home / "fail-encoder").touch()
    assert run("record", "toggle", "--output", "TEST-1", check=False).returncode != 0
    assert not alive(int((home / "encoder.pid").read_text()))
    (home / "fail-encoder").unlink()

    # Bad oldest image does not poison subsequent local OCR. Files are synthetic.
    images = home / "Pictures/mark-shot"
    images.mkdir(parents=True)
    for i, name in enumerate(["bad.png", "good.png"]):
        f = images / name
        f.write_bytes(b"synthetic image fixture")
        os.utime(f, (1000000000 + i, 1000000000 + i))
    run("index", "--no-ocr")
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
    print("mock runtime: window/region/output, dual audio cleanup, slow notification, encoder failure, OCR retry/pause, private permissions PASS")
