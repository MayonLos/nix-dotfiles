#!/usr/bin/env python3
"""Real Kitty in private headless sway. Never uses the user's Wayland socket.
Run from the repository root; arguments: output-directory [binary].
Requires sway, kitty, grim, dbus-run-session and ImageMagick on PATH.
"""
import fcntl
import glob
import json
import math
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import unicodedata
import threading
import time
import tty

out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)
binary = Path(sys.argv[2] if len(sys.argv) > 2 else "packages/mayon-tui/target/debug/mayon-tools").resolve()
tools = {name: shutil.which(name) for name in ["sway", "swaymsg", "kitty", "grim", "dbus-run-session", "magick"]}
if not all(tools.values()):
    raise SystemExit("Missing tools: " + ", ".join(k for k, v in tools.items() if not v))
root = Path(tempfile.mkdtemp(prefix="serial-mayon-visual-"))
root.chmod(0o700)
runtime = root / "runtime"
runtime.mkdir(mode=0o700)
home = root / "home"
home.mkdir(mode=0o700)
port = root / "mcu-uart"
master, slave = pty.openpty()
tty.setraw(slave)
port.symlink_to(os.ttyname(slave))
config_dir = home / ".config/serial-mayon"
config_dir.mkdir(parents=True, mode=0o700)
profile = {"settings": {"baud": 115200, "bits": 8, "parity": "none", "stop": 1, "flow": "none", "dtr": False, "rts": False}, "encoding": "Utf8", "ending": "CRLF", "flash": "printf 'SIMULATED FLASH: UART released\\n'; sleep 1; printf 'verify OK · reconnect UART\\n'", "flash_dir": str(root)}
(config_dir / "config.json").write_text(json.dumps({"devices": {f"0000:0000:{port}:": profile}, "favorites": [{"name": "读取状态", "value": "status", "hex": False}, {"name": "STM32 bootloader sync", "value": "7F", "hex": True}], "highlights": ["ERROR", "WARN", "FAULT"], "scrollback": 100000}))
base = {"PATH": os.environ.get("PATH", ""), "HOME": str(home), "XDG_RUNTIME_DIR": str(runtime), "XDG_CONFIG_HOME": str(home / ".config"), "XDG_DATA_HOME": str(home / ".local/share"), "XDG_CACHE_HOME": str(home / ".cache"), "LANG": "C.UTF-8", "XDG_SESSION_TYPE": "wayland", "WLR_BACKENDS": "headless", "WLR_RENDERER": "pixman", "WLR_LIBINPUT_NO_DEVICES": "1"}
def clean(argv, values=None, **kwargs):
    env = base | (values or {})
    return subprocess.run(["env", "-i", *(f"{k}={v}" for k, v in env.items()), *map(str, argv)], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, **kwargs)
config = root / "sway.conf"
config.write_text("output HEADLESS-1 mode 2560x1600 scale 1.5\nseat seat0 fallback true\nfont monospace 10\ndefault_border none\nfocus_follows_mouse no\noutput * bg #181b20 solid_color\n")
log = open(out / "sway.log", "wb")
sway = subprocess.Popen(["env", "-i", *(f"{k}={v}" for k, v in base.items()), tools["dbus-run-session"], "sh", "-c", 'printf "%s" "$DBUS_SESSION_BUS_ADDRESS" > "$1"; exec "$2" --unsupported-gpu -c "$3"', "serial-visual", str(root / "bus.address"), tools["sway"], str(config)], stdout=log, stderr=log, start_new_session=True)
kitty = None
stop = threading.Event()
fd_lock = threading.Lock()
def feed():
    n = 0
    while not stop.wait(0.08):
        with fd_lock:
            fd = master
        if fd is None:
            continue
        try:
            if n % 11 == 0:
                msg = f"\x1b[32mINFO\x1b[0m PTY 模拟 STM32 · tick={n} · 系统运行中\r\n"
            elif n % 29 == 0:
                msg = "\x1b[33mWARN\x1b[0m ADC 电压接近阈值 · 检查采样窗口\r\n"
            elif n % 53 == 0:
                msg = "\x1b[31mERROR\x1b[0m simulated timeout · 已恢复\r\n"
            else:
                msg = f"temp={26+2*math.sin(n/12):.2f},vbat={3.3+0.25*math.cos(n/9):.3f}\r\n"
            os.write(fd, msg.encode())
            readable, _, _ = select.select([fd], [], [], 0)
            if readable:
                received = os.read(fd, 4096)
                if received:
                    os.write(fd, b"ACK " + received + b"\r\n")
            n += 1
        except OSError:
            pass
thread = threading.Thread(target=feed, daemon=True)
shots = []
try:
    deadline = time.monotonic() + 15
    while time.monotonic() < deadline:
        sockets = [p for p in runtime.glob("wayland-*") if not p.name.endswith(".lock")]
        ipc = list(runtime.glob("sway-ipc.*.sock"))
        if sockets and ipc:
            break
        if sway.poll() is not None:
            raise RuntimeError("sway exited; inspect sway.log")
        time.sleep(0.1)
    else:
        raise RuntimeError("sway socket timed out")
    extra = {"WAYLAND_DISPLAY": sockets[0].name, "SWAYSOCK": str(ipc[0]), "DBUS_SESSION_BUS_ADDRESS": (root / "bus.address").read_text()}
    remote = root / "kitty.sock"
    kitty_log = open(out / "kitty.log", "wb")
    kitty = subprocess.Popen(["env", "-i", *(f"{k}={v}" for k, v in (base | extra).items()), tools["kitty"], "--config", "NONE", "--listen-on", f"unix:{remote}", "--override", "allow_remote_control=yes", "--override", "linux_display_server=wayland", "--override", "font_family=Maple Mono NF CN", "--override", "font_size=13", "--override", "background=#1e2228", "--override", "foreground=#abb2bf", "--override", "window_padding_width=12", "--class=mayon-tools", "--title=Serial Mayon · PTY simulation", str(binary), "serial", str(port)], stdout=kitty_log, stderr=kitty_log)
    deadline = time.monotonic() + 15
    while not remote.exists() and time.monotonic() < deadline:
        time.sleep(0.1)
    time.sleep(1)
    thread.start()
    def send(text):
        clean([tools["kitty"], "@", "--to", f"unix:{remote}", "send-text", "--", text], extra)
        time.sleep(0.25)
    def shot(name):
        time.sleep(0.5)
        clean([tools["grim"], "-o", "HEADLESS-1", str(out / (name + ".png"))], extra)
        screen = clean([tools["kitty"], "@", "--to", f"unix:{remote}", "get-text"], extra).stdout.decode()
        (out / (name + ".txt")).write_text(screen)
        shots.append(name)
    send("cl")
    time.sleep(3)
    shot("01-monitor-round1")
    send("istatus\r")
    send("xiDE AD 00 FF\r")
    send("t\x15250\r")
    time.sleep(0.8)
    send("t\x150\r")
    payload = root / "payload.bin"
    payload.write_bytes(b"FILE-PAYLOAD\x00\xff\r\n")
    send("F" + str(payload) + "\r")
    shot("01b-send-timer-file")
    send("\x06WARN\r")
    shot("02-search-round1")
    send("\x1b[F")
    send("3")
    shot("03-settings-round1")
    send("4")
    shot("04-commands-round1")
    send("1vv")
    shot("05-hex-round1")
    send("v")
    # Simulate hot unplug: new PTY, same stable alias, actual EIO on the old fd.
    with fd_lock:
        os.close(master)
        os.close(slave)
        master = None
        port.unlink()
    time.sleep(1)
    shot("06-disconnected-round1")
    with fd_lock:
        master, slave = pty.openpty()
        tty.setraw(slave)
        port.symlink_to(os.ttyname(slave))
    time.sleep(1.5)
    shot("07-reconnected-round1")
    send("\x1b[15~")
    time.sleep(1.5)
    shot("08-flash-round1")
    send("1")
    clean([tools["swaymsg"], "-s", str(ipc[0]), "[app_id=mayon-tools] floating enable"], extra)
    time.sleep(0.5)
    # Wayland compositors own floating geometry. Resize through this private
    # sway socket, then measure real terminal cells from its full-width border.
    width = 1010
    for attempt in range(8):
        clean([tools["swaymsg"], "-s", str(ipc[0]), f"[app_id=mayon-tools] resize set width {width} px height 990 px"], extra)
        time.sleep(0.35)
        screen = clean([tools["kitty"], "@", "--to", f"unix:{remote}", "get-text"], extra).stdout.decode()
        columns = max(sum(2 if unicodedata.east_asian_width(ch) in ("W", "F") else 1 for ch in line) for line in screen.splitlines())
        if columns == 90:
            break
        width += (90 - columns) * 11
    if columns != 90:
        raise RuntimeError(f"Expected 90 columns, got {columns}")
    (out / "narrow-metrics.json").write_text(json.dumps({"columns": columns, "sway_width": width, "rows": len(screen.splitlines())}))
    shot("09-narrow-round1")
    send("?")
    shot("10-help-round1")
    send("?q")
finally:
    stop.set()
    if thread.is_alive():
        thread.join(timeout=2)
    if kitty is not None:
        kitty.terminate()
        try:
            kitty.wait(timeout=3)
        except subprocess.TimeoutExpired:
            kitty.kill()
    os.killpg(sway.pid, signal.SIGTERM)
    try:
        sway.wait(timeout=3)
    except subprocess.TimeoutExpired:
        os.killpg(sway.pid, signal.SIGKILL)
    for fd in [master, slave]:
        if fd is not None:
            try:
                os.close(fd)
            except OSError:
                pass
    log.close()
# Artifacts contain only simulated data; keep diagnostics and private config.
(out / "simulation.json").write_text(json.dumps({"resolution": "2560x1600", "scale": 1.5, "terminal": "real kitty", "input": "PTY simulator", "runtime": str(root), "shots": shots}, indent=2))
(out / "gallery.html").write_text("<!doctype html><meta charset=utf-8><title>Serial Mayon · isolated PTY</title><style>body{background:#1e2228;color:#abb2bf;font:18px sans-serif;margin:30px}img{width:100%;border:1px solid #5c6370}section{margin:40px 0}</style><h1>Serial Mayon · 真实 Kitty / 隔离 sway / PTY 模拟</h1>" + "".join(f'<section><h2>{name}</h2><a href="{name}.png"><img src="{name}.png"></a></section>' for name in shots))
clean([tools["magick"], "montage", *[str(out / (name + ".png")) for name in shots], "-thumbnail", "640x400", "-tile", "2x", "-geometry", "+8+8", "-background", "#181b20", str(out / "overview.png")])
print(out / "gallery.html")
