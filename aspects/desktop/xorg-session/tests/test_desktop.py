#!/usr/bin/env python3
"""Exercise the real configured WM and X11 parsers on an isolated Xvfb bus.

No session supervisor, user manager, login session or production services run.
The XRender override tests Picom configuration, not the production GLX driver.
"""

import ctypes as C
import json
import os
import re
from pathlib import Path
import subprocess
import sys
import time


programs = json.loads(Path(sys.argv[1]).read_text())
output = Path(sys.argv[2])
m = json.loads(Path(sys.argv[3]).read_text())
palette = programs["palette"]
assert programs["wallpaper"] == m["wallpaper"] == m["greeterWallpaper"]
config_header = Path(programs["dwmConfig"]).read_text()
for key, role in {
    "selfgcolor": "blue", "selbgcolor": "selection", "selbordercolor": "blue",
    "titleselfgcolor": "blue", "titleselbgcolor": "selection", "titleselbordercolor": "blue",
    "tagsselfgcolor": "blue", "tagsselbgcolor": "selection", "tagsselbordercolor": "blue",
}.items():
    assert re.search(rf'static char {key}\[\]\s*= "{re.escape(palette[role])}";', config_header), key
dmenu_config = Path(programs["dmenu"]).read_text()
assert re.search(rf"-sb\s+'{re.escape(palette['selection'])}'", dmenu_config)
assert re.search(rf"-sf\s+'{re.escape(palette['blue'])}'", dmenu_config)
assert m['defaultSession'] == 'Mango'
assert m['xserver'] and m['startx'] and not m['generatedXinitrc'] and m['pam']
assert not m['rofiEnabled'], 'B uses dmenu; the old Rofi renderer must be absent'
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


def start(name, args, **kwargs):
    stream = (output / (name + ".log")).open("w")
    streams.append(stream)
    child = subprocess.Popen(args, stdout=stream, stderr=subprocess.STDOUT, **kwargs)
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
x.XSetTransientForHint.argtypes = [C.c_void_p, C.c_ulong, C.c_ulong]
x.XDestroyWindow.argtypes = [C.c_void_p, C.c_ulong]
x.XSync.argtypes = [C.c_void_p, C.c_int]
x.XCloseDisplay.argtypes = [C.c_void_p]
display = x.XOpenDisplay(None)
assert display, "isolated X server is unavailable"
root = x.XDefaultRootWindow(display)


def atom(name):
    return x.XInternAtom(display, name.encode(), 0)


def window(name, klass, dialog=False, transient_for=None, width=640, height=420):
    result = x.XCreateSimpleWindow(display, root, 0, 0, width, height, 0, 0, int(palette["bg"].removeprefix("#"), 16))
    wm_class = (klass.lower() + "\0" + klass + "\0").encode()
    x.XChangeProperty(display, result, atom("WM_CLASS"), atom("STRING"), 8, 0, wm_class, len(wm_class))
    x.XStoreName(display, result, name.encode())
    if dialog:
        value = C.c_ulong(atom("_NET_WM_WINDOW_TYPE_DIALOG"))
        x.XChangeProperty(display, result, atom("_NET_WM_WINDOW_TYPE"), atom("ATOM"), 32, 0, C.byref(value), 1)
    if transient_for is not None:
        x.XSetTransientForHint(display, result, transient_for)
    x.XMapWindow(display, result)
    x.XSync(display, 0)
    return result


try:
    subprocess.run([programs["xrdb"], "-merge"], input=f"Xft.dpi: {m['x11Dpi']}\n", text=True, check=True)
    wm = start("dwm", [programs["dwm"]])
    eventually(lambda: wm.poll() is None and "window id" in prop(root, "_NET_SUPPORTING_WM_CHECK"), "dwm did not become EWMH-ready")
    first = window("Xorg fixture one", "XorgFixture")
    eventually(lambda: "= 0" in prop(first, "_MAYON_DWM_FLOATING") and geometry(first)["Width"] > 1200, "single window was not tiled")
    single = geometry(first)
    assert single["Absolute upper-left X"] >= round(14 * m["x11Dpi"] / 96), "single-window outer gap disappeared"
    second = window("Xorg fixture two", "XorgFixture")
    eventually(lambda: str(hex(first)) in prop(root, "_NET_CLIENT_LIST") and str(hex(second)) in prop(root, "_NET_CLIENT_LIST"), "WM did not manage both fixture clients")
    eventually(lambda: geometry(first)["Width"] < 1500 and geometry(second)["Width"] < 1500, "two clients were not tiled")
    tiled = [geometry(first), geometry(second)]
    assert all(g["Absolute upper-left X"] > 0 for g in tiled), tiled
    assert prop(first, "_MAYON_DWM_FLOATING").endswith("= 0")
    dialog = window("Xorg fixture dialog", "Pavucontrol", dialog=True)
    eventually(lambda: prop(dialog, "_MAYON_DWM_FLOATING").endswith("= 1"), "dialog rule did not enable floating")
    g = geometry(dialog)
    assert 0.60 <= g['Width'] / 1600 <= 0.70, ('utility initial size', g)
    assert abs(g['Absolute upper-left X'] + g['Width'] / 2 - 800) < 40, g
    subprocess.run([programs["xdotool"], "key", "super+shift+space"], check=True)
    eventually(lambda: prop(dialog, "_MAYON_DWM_FLOATING").endswith("= 0"), "floating toggle did not update the client atom")
    subprocess.run([programs["xdotool"], "key", "super+shift+space"], check=True)
    eventually(lambda: prop(dialog, "_MAYON_DWM_FLOATING").endswith("= 1"), "second floating toggle did not restore the client atom")
    eventually(lambda: geometry(dialog) == g, "saved floating geometry was lost")
    subprocess.run([programs["xdotool"], "key", "super+f"], check=True)
    eventually(lambda: '_NET_WM_STATE_FULLSCREEN' in prop(dialog, '_NET_WM_STATE'), "fullscreen key did not set EWMH state")
    eventually(lambda: geometry(dialog)['Width'] == 1600, "fullscreen did not cover the output")
    subprocess.run([programs["xdotool"], "key", "super+f"], check=True)
    eventually(lambda: '_NET_WM_STATE_FULLSCREEN' not in prop(dialog, '_NET_WM_STATE'), "fullscreen did not exit")
    eventually(lambda: geometry(dialog) == g, "fullscreen exit lost the original floating geometry")
    subprocess.run([programs["xdotool"], "key", "super+2"], check=True)
    subprocess.run([programs["xdotool"], "windowactivate", "--sync", str(first)], check=True, timeout=5)
    eventually(lambda: hex(first) in prop(root, "_NET_ACTIVE_WINDOW"), "pager could not activate a client on another tag")
    # A generic child dialog must float over its actual parent even without
    # a special class or _NET_WM_WINDOW_TYPE hint. Main app classes stay tiled.
    parent_geometry = geometry(first)
    transient = window("Xorg transient fixture", "XorgTransient", transient_for=first, width=320, height=200)
    eventually(lambda: prop(transient, "_MAYON_DWM_FLOATING").endswith("= 1"), "parented dialog was tiled")
    child_geometry = geometry(transient)
    for axis, dimension in (("Absolute upper-left X", "Width"), ("Absolute upper-left Y", "Height")):
        assert abs(child_geometry[axis] + child_geometry[dimension] / 2 - parent_geometry[axis] - parent_geometry[dimension] / 2) < 20, (parent_geometry, child_geometry)
    x.XDestroyWindow(display, transient)
    x.XSync(display, 0)
    for klass in ("QQ", "wemeetapp", "jetbrains-idea"):
        app = window("Main window fixture", klass)
        eventually(lambda: prop(app, "_MAYON_DWM_FLOATING").endswith("= 0"), f"{klass} main window was forced floating")
        x.XDestroyWindow(display, app)
        x.XSync(display, 0)
    utility = window("Qt settings fixture", "qt6ct")
    eventually(lambda: prop(utility, "_MAYON_DWM_FLOATING").endswith("= 1"), "Qt settings rule did not float")
    assert 0.60 <= geometry(utility)["Width"] / 1600 <= 0.70, geometry(utility)
    x.XDestroyWindow(display, utility)
    x.XSync(display, 0)
    subprocess.run([programs["xdotool"], "windowactivate", "--sync", str(dialog)], check=True, timeout=5)
    # Exercise the actual j4 + dmenu launcher against one safe desktop entry.
    # This checks app selection and desktop Exec argv without launching user apps.
    fixture_data = output / "launcher-data"
    applications = fixture_data / "applications"
    applications.mkdir(parents=True)
    probe = output / "launcher-probe.py"
    marker = output / "launcher-argv.json"
    probe.write_text("import json,sys\nfrom pathlib import Path\nPath(sys.argv[1]).write_text(json.dumps(sys.argv[2:]))\n")
    (applications / "fixture.desktop").write_text(
        '[Desktop Entry]\nType=Application\nName=配置检查\nTerminal=false\n'
        f'Exec={sys.executable} {probe} {marker} "中文 文件" "a;b"\n'
    )
    launcher_env = dict(os.environ, XDG_DATA_HOME=str(fixture_data), XDG_DATA_DIRS=str(fixture_data / "secondary"), XDG_CURRENT_DESKTOP="dwm")
    (fixture_data / "secondary").mkdir()
    launcher = start("launcher", [programs["launcher"]], env=launcher_env)
    eventually(lambda: subprocess.run([programs["xdotool"], "search", "--onlyvisible", "--class", "dmenu"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0, "dmenu launcher did not map")
    menu_windows = subprocess.check_output([programs["xdotool"], "search", "--onlyvisible", "--class", "dmenu"], text=True).splitlines()
    menu_geometry = geometry(int(menu_windows[-1]))
    assert menu_geometry['Width'] < 900 and menu_geometry['Absolute upper-left X'] > 300, menu_geometry
    assert abs(menu_geometry['Absolute upper-left X'] + menu_geometry['Width'] / 2 - 800) < 10, menu_geometry
    subprocess.run([programs["maim"], str(output / "launcher-preview.png")], check=True)
    subprocess.run([programs["xdotool"], "key", "--clearmodifiers", "Return"], check=True)
    assert launcher.wait(timeout=5) == 0, "j4 launcher failed"
    eventually(marker.exists, "desktop Exec was not launched")
    assert json.loads(marker.read_text()) == ["中文 文件", "a;b"], marker.read_text()
    picom = start("picom", [programs["picom"], "--config", programs["picomConfig"], "--backend", "xrender"])
    dunst = start("dunst", [programs["dunst"], "-config", programs["dunstConfig"]])
    time.sleep(1)
    assert picom.poll() is None, "Picom failed to parse/start with XRender"
    assert dunst.poll() is None, "Dunst failed to parse/start on isolated D-Bus"
    subprocess.run(["dbus-send", "--session", "--print-reply", "--dest=org.freedesktop.Notifications", "/org/freedesktop/Notifications", "org.freedesktop.Notifications.GetServerInformation"], check=True, stdout=(output / "notification-server.txt").open("w"), timeout=10)
    subprocess.run([programs["feh"], "--no-fehbg", "--bg-fill", programs["wallpaper"]], check=True)
    subprocess.run([programs["xsetroot"], "-name", f"^c{palette['muted']}^^d^ 45%  ·  BAT 80%  ·  ^c{palette['blue']}^12:00^d^"], check=True)
    # Render the production menu but cancel it: none of its actions run.
    menu = start("menu-preview", [programs["menu"]])
    eventually(lambda: subprocess.run([programs["xdotool"], "search", "--onlyvisible", "--class", "dmenu"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0, "production menu did not map")
    subprocess.run([programs["notifySend"], "Xorg · One Dark", "隔离显示检查：浮窗、启动器与通知。"], check=True)
    time.sleep(0.6)
    assert menu.poll() is None, "dmenu preview could not render"
    subprocess.run([programs["maim"], str(output / "desktop-preview.png")], check=True)
    subprocess.run([programs["xdotool"], "key", "--clearmodifiers", "Escape"], check=True)
    assert menu.wait(timeout=5) == 0, "menu cancellation failed"
    eventually(lambda: subprocess.run([programs["xdotool"], "search", "--onlyvisible", "--class", "dmenu"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0, "cancelled menu remained mapped")
    time.sleep(0.3)  # Give the isolated compositor time to repaint the damage.
    subprocess.run([programs["maim"], str(output / "desktop-clean-preview.png")], check=True)
    # Arbitrary dmenu text must not become a shell command in the control menu.
    menu = start("menu-unknown", [programs["menu"]])
    eventually(lambda: subprocess.run([programs["xdotool"], "search", "--onlyvisible", "--class", "dmenu"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0, "second control menu did not map")
    canary = output / "must-not-exist"
    subprocess.run([programs["xdotool"], "type", "--clearmodifiers", f"touch {canary}"], check=True)
    subprocess.run([programs["xdotool"], "key", "--clearmodifiers", "Return"], check=True)
    assert menu.wait(timeout=5) == 0 and not canary.exists(), "unknown control-menu text was executed"
    (output / "geometry.json").write_text(json.dumps({"single": single, "tiled": tiled, "dialog": geometry(dialog), "menu": menu_geometry}, indent=2))
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
