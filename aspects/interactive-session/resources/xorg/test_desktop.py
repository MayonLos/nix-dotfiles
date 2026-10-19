#!/usr/bin/env python3
"""Exercise the real configured WM and X11 parsers on an isolated Xvfb bus.

No session supervisor, user manager, login session or production services run.
The XRender override tests Picom configuration, not the production GLX driver.
"""

import ctypes as C
import json
import re
from pathlib import Path
import subprocess
import sys
import time


programs = json.loads(Path(sys.argv[1]).read_text())
output = Path(sys.argv[2])
m = json.loads(Path(sys.argv[3]).read_text())
assert m['defaultSession'] == 'Mango'
assert m['xserver'] and m['startx'] and not m['generatedXinitrc'] and m['pam']
assert set(m['sharedTargets']) == {'mango-session.target', 'xorg-session.target'}
for name, unit in m['units'].items():
    for key in ('PartOf', 'After', 'Requisite'):
        assert unit['Unit'][key] == ['xorg-session.target'], (name, key)
    assert unit['Unit']['ConditionEnvironment'] == 'XDG_CURRENT_DESKTOP=dwm'
    assert unit['Install']['WantedBy'] == ['xorg-session.target']
assert m['portal']['org.freedesktop.impl.portal.ScreenCast'] == 'none'
identifiers = re.findall(r'^\s*Identifier\s+"([^"]+)"', m['xorgConfig'], re.MULTILINE)
assert len(identifiers) == len(set(identifiers)), "duplicate Xorg section identifiers"
assert m['xorgConfig'].count('Screen "Screen-modesetting[0]"') == 1
children = []
streams = []


def start(name, args):
    stream = (output / (name + ".log")).open("w")
    streams.append(stream)
    child = subprocess.Popen(args, stdout=stream, stderr=subprocess.STDOUT)
    children.append(child)
    return child


def eventually(predicate, description):
    deadline = time.monotonic() + 8
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.05)
    raise AssertionError(description)


def prop(window, name):
    return subprocess.check_output(
        [programs["xprop"], "-id", str(window), name], text=True
    ).strip()


def geometry(window):
    text = subprocess.check_output(
        [programs["xwininfo"], "-id", str(window)], text=True
    )
    fields = {}
    for line in text.splitlines():
        key, sep, value = line.strip().partition(":")
        if sep and key in ("Absolute upper-left X", "Absolute upper-left Y", "Width", "Height"):
            fields[key] = int(value.strip())
    return fields


x = C.CDLL(programs["xlib"])
x.XOpenDisplay.argtypes = [C.c_char_p]
x.XOpenDisplay.restype = C.c_void_p
x.XDefaultRootWindow.argtypes = [C.c_void_p]
x.XDefaultRootWindow.restype = C.c_ulong
x.XInternAtom.argtypes = [C.c_void_p, C.c_char_p, C.c_int]
x.XInternAtom.restype = C.c_ulong
x.XCreateSimpleWindow.argtypes = [C.c_void_p, C.c_ulong, C.c_int, C.c_int, C.c_uint, C.c_uint, C.c_uint, C.c_ulong, C.c_ulong]
x.XCreateSimpleWindow.restype = C.c_ulong
x.XChangeProperty.argtypes = [C.c_void_p, C.c_ulong, C.c_ulong, C.c_ulong, C.c_int, C.c_int, C.c_void_p, C.c_int]
x.XStoreName.argtypes = [C.c_void_p, C.c_ulong, C.c_char_p]
x.XMapWindow.argtypes = [C.c_void_p, C.c_ulong]
x.XSync.argtypes = [C.c_void_p, C.c_int]
x.XCloseDisplay.argtypes = [C.c_void_p]
display = x.XOpenDisplay(None)
assert display, "isolated X server is unavailable"
root = x.XDefaultRootWindow(display)


def atom(name):
    return x.XInternAtom(display, name.encode(), 0)


def window(name, klass, dialog=False):
    result = x.XCreateSimpleWindow(display, root, 0, 0, 640, 420, 0, 0, 0x1F2329)
    wm_class = (klass.lower() + "\0" + klass + "\0").encode()
    x.XChangeProperty(display, result, atom("WM_CLASS"), atom("STRING"), 8, 0, wm_class, len(wm_class))
    x.XStoreName(display, result, name.encode())
    if dialog:
        value = C.c_ulong(atom("_NET_WM_WINDOW_TYPE_DIALOG"))
        x.XChangeProperty(display, result, atom("_NET_WM_WINDOW_TYPE"), atom("ATOM"), 32, 0, C.byref(value), 1)
    x.XMapWindow(display, result)
    x.XSync(display, 0)
    return result


try:
    wm = start("dwm", [programs["dwm"]])
    eventually(lambda: wm.poll() is None and "window id" in prop(root, "_NET_SUPPORTING_WM_CHECK"), "dwm did not become EWMH-ready")
    first = window("Xorg fixture one", "XorgFixture")
    second = window("Xorg fixture two", "XorgFixture")
    eventually(lambda: str(hex(first)) in prop(root, "_NET_CLIENT_LIST") and str(hex(second)) in prop(root, "_NET_CLIENT_LIST"), "WM did not manage both fixture clients")
    eventually(lambda: geometry(first)["Width"] < 1500 and geometry(second)["Width"] < 1500, "two clients were not tiled")
    tiled = [geometry(first), geometry(second)]
    assert all(g["Absolute upper-left X"] > 0 for g in tiled), tiled
    assert prop(first, "_MAYON_DWM_FLOATING").endswith("= 0")
    dialog = window("Xorg fixture dialog", "Pavucontrol", dialog=True)
    eventually(lambda: prop(dialog, "_MAYON_DWM_FLOATING").endswith("= 1"), "dialog rule did not enable floating")
    g = geometry(dialog)
    assert abs(g['Absolute upper-left X'] + g['Width'] / 2 - 800) < 40, g
    subprocess.run([programs["xdotool"], "key", "super+shift+space"], check=True)
    eventually(lambda: prop(dialog, "_MAYON_DWM_FLOATING").endswith("= 0"), "floating toggle did not update the client atom")
    subprocess.run([programs["xdotool"], "key", "super+shift+space"], check=True)
    eventually(lambda: prop(dialog, "_MAYON_DWM_FLOATING").endswith("= 1"), "second floating toggle did not restore the client atom")
    assert geometry(dialog)['Width'] == g['Width'], "saved floating size was lost"
    subprocess.run([programs["xdotool"], "key", "super+f"], check=True)
    eventually(lambda: '_NET_WM_STATE_FULLSCREEN' in prop(dialog, '_NET_WM_STATE'), "fullscreen key did not set EWMH state")
    eventually(lambda: geometry(dialog)['Width'] == 1600, "fullscreen did not cover the output")
    subprocess.run([programs["xdotool"], "key", "super+f"], check=True)
    eventually(lambda: '_NET_WM_STATE_FULLSCREEN' not in prop(dialog, '_NET_WM_STATE'), "fullscreen did not exit")
    eventually(lambda: geometry(dialog)['Width'] == g['Width'], "fullscreen exit lost the original floating geometry")
    subprocess.run([programs["xdotool"], "key", "super+2"], check=True)
    subprocess.run([programs["xdotool"], "windowactivate", "--sync", str(first)], check=True, timeout=5)
    eventually(lambda: hex(first) in prop(root, "_NET_ACTIVE_WINDOW"), "pager could not activate a client on another tag")
    subprocess.run([programs["xdotool"], "key", "super+2"], check=True)
    picker = start("rofi-window", [programs["rofi"], "-config", programs["rofiConfig"], "-show", "window", "-filter", "Xorg fixture one"])
    eventually(lambda: subprocess.run([programs["xdotool"], "search", "--onlyvisible", "--class", "rofi"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0, "Rofi window picker did not map")
    time.sleep(0.3)
    subprocess.run([programs["xdotool"], "key", "--clearmodifiers", "Return"], check=True)
    assert picker.wait(timeout=5) == 0, "Rofi window picker failed"
    eventually(lambda: hex(first) in prop(root, "_NET_ACTIVE_WINDOW"), "Rofi could not select a client on another tag")
    subprocess.run([programs["rofi"], "-config", programs["rofiConfig"], "-dump-theme"], check=True, stdout=(output / "rofi-theme.rasi").open("w"), stderr=(output / "rofi.log").open("w"), timeout=15)
    picom = start("picom", [programs["picom"], "--config", programs["picomConfig"], "--backend", "xrender"])
    dunst = start("dunst", [programs["dunst"], "-config", programs["dunstConfig"]])
    time.sleep(1)
    assert picom.poll() is None, "Picom failed to parse/start with XRender"
    assert dunst.poll() is None, "Dunst failed to parse/start on isolated D-Bus"
    subprocess.run(["dbus-send", "--session", "--print-reply", "--dest=org.freedesktop.Notifications", "/org/freedesktop/Notifications", "org.freedesktop.Notifications.GetServerInformation"], check=True, stdout=(output / "notification-server.txt").open("w"), timeout=10)
    subprocess.run([programs["feh"], "--no-fehbg", "--bg-fill", programs["wallpaper"]], check=True)
    subprocess.run([programs["xsetroot"], "-name", "^c#4fa6ed^^d^ 45%  │  BAT 80%  │  10-19 12:00"], check=True)
    # Render the production menu but cancel it: none of its actions run.
    rofi = start("rofi-preview", [programs["menu"]])
    eventually(lambda: subprocess.run([programs["xdotool"], "search", "--onlyvisible", "--class", "rofi"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0, "production menu did not map")
    subprocess.run([programs["notifySend"], "Xorg · One Dark", "隔离显示检查：浮窗、启动器与通知。"], check=True)
    time.sleep(0.6)
    assert rofi.poll() is None, "Rofi preview could not render"
    subprocess.run([programs["maim"], str(output / "desktop-preview.png")], check=True)
    subprocess.run([programs["xdotool"], "key", "--clearmodifiers", "Escape"], check=True)
    assert rofi.wait(timeout=5) == 0, "menu cancellation failed"
    (output / "geometry.json").write_text(json.dumps({"tiled": tiled, "dialog": geometry(dialog)}, indent=2))
    (output / "scope.txt").write_text("Real dwm + parser/XRender smoke under Xvfb. No real Xorg/GLX/PAM/capture acceptance.\n")
finally:
    x.XCloseDisplay(display)
    for child in reversed(children):
        if child.poll() is None:
            child.terminate()
    for child in reversed(children):
        try:
            child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            # Only an owned isolated fixture process can reach this path.
            child.kill()
            child.wait()
    for stream in streams:
        stream.close()
