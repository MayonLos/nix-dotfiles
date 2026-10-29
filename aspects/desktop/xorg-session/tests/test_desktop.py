#!/usr/bin/env python3
"""Exercise the production dwm/Rofi/status/Dunst stack under isolated Xvfb."""

import configparser
import ctypes as C
import json
import os
from pathlib import Path
import re
import select
import shutil
import subprocess
import sys
import time


programs = json.loads(Path(sys.argv[1]).read_text())
output = Path(sys.argv[2])
m = json.loads(Path(sys.argv[3]).read_text())
palette = programs["palette"]
assert programs["wallpaper"] == m["wallpaper"]
# The greeter uses a blurred, dimmed derivative of the same default image.
assert m["greeterWallpaper"].endswith("-greeter-auth-wallpaper.png")
assert m["defaultSession"] == "Mango"
assert m["xserver"] and m["startx"] and not m["generatedXinitrc"] and m["pam"]
assert set(m["sharedTargets"]) == {"mango-session.target", "xorg-session.target"}
assert "xorg-outputs" in m["units"], "display hotplug watcher must be session-target guarded"
for name, unit in m["units"].items():
    for key in ("PartOf", "After", "Requisite"):
        assert unit["Unit"][key] == ["xorg-session.target"], (name, key)
    assert unit["Unit"]["ConditionEnvironment"] == "XDG_CURRENT_DESKTOP=dwm"
    assert unit["Install"]["WantedBy"] == ["xorg-session.target"]
assert m["portal"]["org.freedesktop.impl.portal.ScreenCast"] == "none"
identifiers = re.findall(r'^\s*Identifier\s+"([^"]+)"', m["xorgConfig"], re.MULTILINE)
assert len(identifiers) == len(set(identifiers)), "duplicate Xorg section identifiers"
assert m["xorgConfig"].count('Screen "Screen-modesetting[0]"') == 1

# Production themes, rule data and generated keymap are the test inputs too.
launcher_theme = Path(programs["launcherTheme"]).read_text()
power_theme = Path(programs["powerTheme"]).read_text()
assert 'placeholder: "搜索"' in launcher_theme and "hide-cursor-on-empty: true" in launcher_theme
assert "width: 840px" in launcher_theme, "560 logical px must scale to 840 pixels at DPI 144"
assert palette["deep"] in launcher_theme and palette["blue"] in launcher_theme
assert "columns: 5" in power_theme
notification_theme = Path(programs["dunstConfig"]).read_text()
notification_config = configparser.ConfigParser(interpolation=None)
notification_config.read_string(notification_theme)
assert notification_config.getint("global", "width") == 320 and notification_config.getboolean("global", "progress_bar")
assert "urgency_critical" in notification_config and notification_config.getint("global", "corner_radius") == 9
picom_theme = Path(programs["picomConfig"]).read_text()
assert "corner-radius = 15" in picom_theme and "shadow = true" in picom_theme
assert "dim = 0.06" in picom_theme
assert "no-custom" in Path(programs["powerMenu"]).read_text()
power_wrapper = Path(programs["powerMenu"]).read_text()
assert 'case "$choice" in' in power_wrapper and "confirmation" in power_wrapper
assert "systemctl" in power_wrapper and "*) exit 0" in power_wrapper
assert all(f"'{label}'" in power_wrapper for label in ("Lock", "Logout", "Suspend", "Reboot", "Shutdown"))
session_wrapper = Path(programs["menu"]).read_text()
assert 'case "$choice" in' in session_wrapper and "-no-custom" in session_wrapper and "*) exit 0" in session_wrapper
launcher_wrapper = Path(programs["launcher"]).read_text()
assert 'mode="${1:-Apps}"' in launcher_wrapper
assert all(f"{mode}" in launcher_wrapper for mode in ("Apps", "Run", "Windows", "Clipboard"))
assert "systemctl" in Path(programs["powerMenu"]).read_text()
rules = json.loads(Path(programs["dwmRules"]).read_text())
assert any(rule.get("title", "").startswith("^(Picture-in-Picture") and rule.get("mayonsticky") == 1 for rule in rules)
assert any(rule.get("mayongame") == 1 and rule.get("bw") == 0 for rule in rules)
assert any(rule.get("mayonpassive") == 1 and "QQ" in rule.get("class", "") for rule in rules)
bindings = json.loads(Path(programs["dwmBindings"]).read_text())
mango = m["mangoBindings"]
assert isinstance(mango, list), "Mango production binding export must remain data"


def chord(mods, key):
    parts = mods.split("+") if mods else []
    return "+".join([*parts, key]).lower()


def mango_chord(value):
    fields = value.split(",")
    if len(fields) < 2:
        return None
    mods = fields[0].replace("NONE", "").replace("SHIFT", "Shift").replace("CTRL", "Ctrl").replace("ALT", "Alt").replace("SUPER", "Super")
    key = fields[1]
    return chord(mods, key)


binding_chords = {chord(row["mods"], row["key"]) for row in bindings}
mango_chords = {item for value in mango if (item := mango_chord(value))}
shared = {
    "super+return", "super+b", "super+e", "super+v", "super+q", "super+space",
    "super+f", "super+shift+f", "super+1", "super+shift+1", "super+ctrl+1",
    "print", "ctrl+print",
}
assert shared <= binding_chords, shared - binding_chords
assert shared <= mango_chords, shared - mango_chords
(output / "keybinding-comparison.json").write_text(json.dumps({
    "shared": sorted(shared), "dwm": sorted(binding_chords), "mango": sorted(mango_chords),
}, indent=2))

children = []
streams = []


def start(name, args, **kwargs):
    stream = (output / (name + ".log")).open("w")
    streams.append(stream)
    child = subprocess.Popen(args, stdout=stream, stderr=subprocess.STDOUT, **kwargs)
    children.append(child)
    return child


def eventually(predicate, description, timeout=10):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.05)
    raise AssertionError(description)


def prop(window, name):
    return subprocess.check_output([programs["xprop"], "-id", str(window), name], text=True).strip()


def root_prop(name):
    return subprocess.check_output([programs["xprop"], "-root", name], text=True).strip()


def geometry(window):
    text = subprocess.check_output([programs["xwininfo"], "-id", str(window)], text=True)
    fields = {}
    for line in text.splitlines():
        key, sep, value = line.strip().partition(":")
        if sep and key in ("Absolute upper-left X", "Absolute upper-left Y", "Width", "Height", "Border width"):
            fields[key] = int(value.strip())
    return fields


def mapped(window):
    info = subprocess.check_output([programs["xwininfo"], "-id", str(window)], text=True)
    return "Map State: IsViewable" in info


def import_root(path):
    subprocess.run([programs["imagemagickImport"], "-window", "root", str(path)], check=True, timeout=15)
    assert path.exists() and path.stat().st_size > 1000


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
    rofi_config_dir = Path(os.environ["XDG_CONFIG_HOME"]) / "rofi"
    rofi_config_dir.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(programs["rofiConfig"], rofi_config_dir / "config.rasi")
    subprocess.run([programs["xrdb"], "-nocpp", "-merge"], input=f"Xft.dpi: {m['x11Dpi']}\n", text=True, check=True)
    wm = start("dwm", [programs["dwm"]])
    eventually(lambda: wm.poll() is None and "window id" in root_prop("_NET_SUPPORTING_WM_CHECK"), "dwm did not become EWMH-ready")
    status = start("status", [programs["status"]])
    eventually(lambda: "UTF8_STRING" in root_prop("_MAYON_DWM_CLOCK"), "status did not publish a UTF-8 clock property")
    eventually(lambda: "^c" in root_prop("WM_NAME"), "status did not publish colored root status")
    assert "UTF8_STRING" in root_prop("_MAYON_DWM_CLOCK")

    first = window("Xorg fixture one", "XorgFixture")
    eventually(lambda: prop(first, "_MAYON_DWM_FLOATING").endswith("= 0") and geometry(first)["Width"] > 1200, "single window was not tiled")
    single = geometry(first)
    second = window("Xorg fixture two", "XorgFixture")
    eventually(lambda: geometry(first)["Width"] < 0.75 * 2560 and geometry(second)["Width"] < 0.75 * 2560, "two clients were not tiled")
    tiled = [geometry(first), geometry(second)]
    assert all(g["Absolute upper-left X"] > 0 for g in tiled), tiled

    dialog = window("Xorg fixture dialog", "Pavucontrol", dialog=True)
    eventually(lambda: prop(dialog, "_MAYON_DWM_FLOATING").endswith("= 1"), "dialog rule did not enable floating")
    g = geometry(dialog)
    assert 0.30 <= g["Width"] / 2560 <= 0.40, ("Pavucontrol utility initial size", g)
    subprocess.run([programs["xdotool"], "windowactivate", "--sync", str(dialog)], check=True, timeout=5)
    subprocess.run([programs["xdotool"], "key", "super+space"], check=True)
    eventually(lambda: prop(dialog, "_MAYON_DWM_FLOATING").endswith("= 0"), "Super+Space did not tile the client")
    subprocess.run([programs["xdotool"], "key", "super+space"], check=True)
    eventually(lambda: prop(dialog, "_MAYON_DWM_FLOATING").endswith("= 1"), "second Super+Space did not float the client")
    eventually(lambda: geometry(dialog) == g, "saved floating geometry was lost")
    subprocess.run([programs["xdotool"], "key", "super+f"], check=True)
    eventually(lambda: geometry(dialog)["Width"] > 2000, "Super+F did not maximize to the workspace")
    subprocess.run([programs["xdotool"], "key", "super+f"], check=True)
    eventually(lambda: geometry(dialog) == g, "Super+F did not restore its saved floating geometry")
    subprocess.run([programs["xdotool"], "key", "super+shift+f"], check=True)
    eventually(lambda: "_NET_WM_STATE_FULLSCREEN" in prop(dialog, "_NET_WM_STATE"), "Super+Shift+F did not fullscreen")
    eventually(lambda: geometry(dialog)["Width"] == 2560, "fullscreen did not cover the Xvfb output")
    subprocess.run([programs["xdotool"], "key", "super+shift+f"], check=True)
    eventually(lambda: "_NET_WM_STATE_FULLSCREEN" not in prop(dialog, "_NET_WM_STATE"), "fullscreen did not exit")
    eventually(lambda: geometry(dialog) == g, "fullscreen exit lost original floating geometry")

    # Float-layout clients retain isfloating=0; local geometry commands must
    # still move them and keep SAVEFLOATS in sync across the next arrange().
    subprocess.run([programs["xdotool"], "windowactivate", "--sync", str(first)], check=True, timeout=5)
    subprocess.run([programs["xdotool"], "key", "super+shift+t"], check=True)
    time.sleep(0.2)
    float_before = geometry(first)
    subprocess.run([programs["xdotool"], "key", "super+shift+Right"], check=True)
    eventually(lambda: geometry(first)["Absolute upper-left X"] > float_before["Absolute upper-left X"], "Float layout did not move its ordinary client")
    float_moved = geometry(first)
    subprocess.run([programs["xdotool"], "key", "super+f"], check=True)
    eventually(lambda: geometry(first)["Width"] > 2400, "Float layout undid workarea maximization")
    subprocess.run([programs["xdotool"], "key", "super+f"], check=True)
    eventually(lambda: geometry(first) == float_moved, "Float layout lost restored geometry")
    subprocess.run([programs["xdotool"], "key", "super+c"], check=True)
    eventually(lambda: abs(geometry(first)["Absolute upper-left X"] + geometry(first)["Width"] / 2 - 1280) < 10, "Float layout did not center its client")
    float_centered = geometry(first)
    arrange_probe = window("Float arrange probe", "XorgFixture")
    time.sleep(0.2)
    assert geometry(first) == float_centered, "SAVEFLOATS undid local geometry on arrange"
    x.XDestroyWindow(display, arrange_probe)
    x.XSync(display, 0)
    subprocess.run([programs["xdotool"], "key", "super+t"], check=True)

    # The pager path is exercised without invoking any configured spawn binding.
    subprocess.run([programs["xdotool"], "key", "super+2"], check=True)
    subprocess.run([programs["xdotool"], "windowactivate", "--sync", str(first)], check=True, timeout=5)
    eventually(lambda: hex(first) in root_prop("_NET_ACTIVE_WINDOW"), "pager could not activate a client on another tag")

    parent_geometry = geometry(first)
    transient = window("Xorg transient fixture", "XorgTransient", transient_for=first, width=320, height=200)
    eventually(lambda: prop(transient, "_MAYON_DWM_FLOATING").endswith("= 1"), "parented dialog was tiled")
    child_geometry = geometry(transient)
    for axis, dimension in (("Absolute upper-left X", "Width"), ("Absolute upper-left Y", "Height")):
        assert abs(child_geometry[axis] + child_geometry[dimension] / 2 - parent_geometry[axis] - parent_geometry[dimension] / 2) < 20, (parent_geometry, child_geometry)
    x.XDestroyWindow(display, transient)
    x.XSync(display, 0)

    subprocess.run([programs["xdotool"], "mousemove", "2300", "1400"], check=True)
    time.sleep(0.2)
    active_before_pip = root_prop("_NET_ACTIVE_WINDOW")
    pip = window("Picture-in-Picture", "Firefox", width=480, height=270)
    eventually(lambda: prop(pip, "_MAYON_DWM_FLOATING").endswith("= 1"), "PiP window was not floating")
    eventually(lambda: root_prop("_NET_ACTIVE_WINDOW") == active_before_pip, "PiP stole keyboard focus instead of remaining silent")
    pip_geometry = geometry(pip)
    subprocess.run([programs["xdotool"], "mousemove", str(pip_geometry["Absolute upper-left X"] + 40), str(pip_geometry["Absolute upper-left Y"] + 40)], check=True)
    time.sleep(0.2)
    assert root_prop("_NET_ACTIVE_WINDOW") == active_before_pip, "pointer-enter stole focus for a passive surface"
    assert any(r.get("mayonsticky") == 1 and r.get("mayonpassive") == 1 for r in rules if r.get("title", "").startswith("^(Picture-in-Picture"))
    subprocess.run([programs["xdotool"], "key", "super+2"], check=True)
    eventually(lambda: mapped(pip), "sticky PiP disappeared when switching tags")
    subprocess.run([programs["xdotool"], "key", "super+1"], check=True)

    active_before_mini = root_prop("_NET_ACTIVE_WINDOW")
    mini = window("Mini Window - fixture", "QQ", width=360, height=240)
    eventually(lambda: prop(mini, "_MAYON_DWM_FLOATING").endswith("= 1"), "communication mini-window did not float")
    eventually(lambda: root_prop("_NET_ACTIVE_WINDOW") == active_before_mini, "communication mini-window stole keyboard focus")
    assert any(r.get("mayonpassive") == 1 and "QQ" in r.get("class", "") for r in rules)
    main = window("QQ Main", "QQ")
    eventually(lambda: prop(main, "_MAYON_DWM_FLOATING").endswith("= 0"), "communication main window was not tiled")
    game = window("Game fixture", "steam_app_1234")
    eventually(lambda: prop(game, "_MAYON_DWM_GAME").endswith("= 1"), "game atom was not set")
    assert geometry(game)["Border width"] == 0

    utility = window("Qt settings fixture", "qt6ct")
    eventually(lambda: prop(utility, "_MAYON_DWM_FLOATING").endswith("= 1"), "Qt settings rule did not float")
    assert 0.59 <= (geometry(utility)["Width"] + 2 * geometry(utility)["Border width"]) / 2560 <= 0.61, geometry(utility)

    # Put the compositor and wallpaper in place before the launcher screenshots
    # so both Rofi previews capture the actual composed production appearance.
    picom = start("picom", [programs["picom"], "--config", programs["picomConfig"], "--backend", "xrender", "--no-use-damage"])
    dunst = start("dunst", [programs["dunst"], "-config", programs["dunstConfig"]])
    time.sleep(1)
    assert picom.poll() is None, "Picom failed to parse/start with XRender"
    assert dunst.poll() is None, "production patched Dunst failed on isolated D-Bus"
    subprocess.run([programs["feh"], "--no-fehbg", "--bg-fill", programs["wallpaper"]], check=True)

    # End behavioral fixtures before visual review. Render three ordinary Xft
    # terminals with fixed public sample text, never a developer login shell.
    for managed in (first, second, dialog, pip, mini, main, game, utility):
        x.XDestroyWindow(display, managed)
    x.XSync(display, 0)
    samples = [
        ("Terminal · native X11", "\033[38;2;97;175;239m~/nix-dotfiles\033[0m  \033[38;2;198;120;221mxorg-rewrite\033[0m\n\033[38;2;152;195;121m❯\033[0m  native X11 capture session\n\n[fixture] dwm · Picom 13 · Rofi 2.0"),
        ("Meeting · capture fixture", "Meeting · native X11 capture\n\nScreen and window capture are application-owned.\nThis is an isolated test window."),
        ("System · status fixture", "System · isolated display\n\n2560 × 1600   Xft.dpi 144\nNo user session or account state is loaded."),
    ]
    for index, (title, text) in enumerate(reversed(samples)):
        code = "import time; print(" + repr(text) + ", flush=True); time.sleep(120)"
        start(f"sample-{index}", [programs["xterm"], "-title", title, "-class", "XorgFixture",
              "-u8", "-xrm", "XTerm.vt100.utf8Title:true", "-xrm", "XTerm.vt100.internalBorder:18",
              "-fa", palette["fonts"]["mono"], "-fs", "10.5", "-bg", palette["bg"],
              "-fg", palette["brightFg"], "-e", sys.executable, "-c", code])
        time.sleep(0.3)
    eventually(lambda: len(re.findall(r"0x[0-9a-f]+", root_prop("_NET_CLIENT_LIST"))) >= 3, "three Xft sample terminals did not map")

    # Launcher mode is passed through. A private desktop fixture is safe to execute.
    fixture_data = output / "launcher-data"
    applications = fixture_data / "applications"
    applications.mkdir(parents=True, exist_ok=True)
    marker = output / "launcher-argv.json"
    probe = output / "launcher-probe.py"
    probe.write_text("import json,sys\nfrom pathlib import Path\nPath(sys.argv[1]).write_text(json.dumps(sys.argv[2:]))\n")
    (applications / "fixture.desktop").write_text(
        "[Desktop Entry]\nType=Application\nName=Kitty\nIcon=kitty\nTerminal=false\n"
        f'Exec={sys.executable} {probe} {marker} "中文 文件" "a;b"\n'
    )
    qq_entry = configparser.ConfigParser(interpolation=None)
    qq_entry.read(programs["qqDesktop"])
    qq_icon = Path(qq_entry["Desktop Entry"]["Icon"])
    assert qq_icon.is_absolute() and qq_icon.is_file(), "QQ package icon fallback must exist independently of the selected theme"
    assert qq_icon.read_bytes().startswith(b"\x89PNG\r\n\x1a\n"), "QQ desktop Icon is not its packaged PNG"
    (output / "qq-icon-source.txt").write_text(str(qq_icon) + "\n")
    for name, source in programs["hiddenDesktopEntries"].items():
        entry = configparser.ConfigParser(interpolation=None)
        entry.read(source)
        assert entry.getboolean("Desktop Entry", "NoDisplay"), name
        shutil.copyfile(source, applications / (name + ".desktop"))
    for desktop_name, display_name, icon in [("qq", "QQ", str(qq_icon)), ("wemeet", "腾讯会议", "wemeet"), ("wechat", "微信", "wechat")]:
        identity = ' "qq"' if desktop_name == "qq" else ""
        (applications / f"{desktop_name}.desktop").write_text(
            f'[Desktop Entry]\nType=Application\nName={display_name}\nIcon={icon}\nTerminal=false\nExec={sys.executable} {probe} {marker} "中文 文件" "a;b"{identity}\n'
        )
    launcher_env = dict(os.environ, XDG_DATA_HOME=str(fixture_data), XDG_DATA_DIRS=str(fixture_data / "secondary") + ":" + os.environ["XDG_DATA_DIRS"], XDG_CURRENT_DESKTOP="dwm")
    (fixture_data / "secondary").mkdir(exist_ok=True)
    launcher = start("launcher", [programs["launcher"], "Apps"], env=launcher_env)
    eventually(lambda: subprocess.run([programs["xdotool"], "search", "--onlyvisible", "--class", "rofi"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0, "Rofi launcher did not map")
    rofi_windows = subprocess.check_output([programs["xdotool"], "search", "--onlyvisible", "--class", "rofi"], text=True).splitlines()
    launcher_id = int(rofi_windows[-1])
    launcher_geometry = geometry(launcher_id)
    assert abs(launcher_geometry["Width"] - 840) < 20, launcher_geometry
    assert abs(launcher_geometry["Absolute upper-left X"] + launcher_geometry["Width"] / 2 - 1280) < 15, launcher_geometry
    time.sleep(0.8)  # map precedes Rofi/icon-worker and compositor first paint
    import_root(output / "launcher.png")
    # Real input must replace the placeholder and retain an ordinary caret.
    subprocess.run([programs["xdotool"], "type", "--clearmodifiers", "QQ"], check=True)
    time.sleep(1.0)
    import_root(output / "launcher-typed.png")
    subprocess.run([programs["xdotool"], "key", "--clearmodifiers", "Return"], check=True)
    launcher_code = launcher.wait(timeout=5)
    assert launcher_code == 0, f"Rofi launcher failed: {launcher_code}"
    eventually(marker.exists, "safe fixture desktop Exec was not launched")
    assert json.loads(marker.read_text()) == ["中文 文件", "a;b", "qq"], "QQ search must launch only the safe QQ fixture"

    # Windows mode must use Rofi's native EWMH activation across tags.
    cross_tag = window("Cross-tag Windows probe", "XorgFixture")
    eventually(lambda: hex(cross_tag) in root_prop("_NET_ACTIVE_WINDOW"), "window fixture did not focus")
    subprocess.run([programs["xdotool"], "key", "super+ctrl+2"], check=True)
    eventually(lambda: geometry(cross_tag)["Absolute upper-left X"] < 0, "silent tagging did not hide the client on the current tag")
    windows_menu = start("windows-menu", [programs["launcher"], "Windows", "-filter", "Cross-tag Windows probe"], env=launcher_env)
    eventually(lambda: subprocess.run([programs["xdotool"], "search", "--onlyvisible", "--class", "rofi"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0, "Windows mode did not map")
    time.sleep(0.4)
    subprocess.run([programs["xdotool"], "key", "--clearmodifiers", "Return"], check=True)
    assert windows_menu.wait(timeout=5) == 0
    eventually(lambda: hex(cross_tag) in root_prop("_NET_ACTIVE_WINDOW"), "Windows mode did not activate a client across tags")
    x.XDestroyWindow(display, cross_tag)
    x.XSync(display, 0)
    subprocess.run([programs["xdotool"], "key", "super+1"], check=True)

    # The clipboard server, database and bus all belong to this test HOME.
    # Exercise the production Rofi script mode against its real pinned CopyQ.
    copyq = start("copyq", [programs["copyq"]], env=dict(os.environ, QT_QPA_PLATFORM="xcb"))
    eventually(lambda: subprocess.run([programs["copyq"], "size"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=2).returncode == 0, "private CopyQ did not start")
    clipboard_fixture = "R24 clipboard fixture 中文"
    subprocess.run([programs["copyq"], "add", clipboard_fixture], check=True, timeout=5)
    clipboard_menu = start("clipboard-menu", [programs["launcher"], "Clipboard", "-filter", "R24 clipboard fixture"], env=launcher_env)
    eventually(lambda: subprocess.run([programs["xdotool"], "search", "--onlyvisible", "--class", "rofi"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0, "Clipboard mode did not map")
    time.sleep(0.6)
    subprocess.run([programs["xdotool"], "key", "--clearmodifiers", "Return"], check=True)
    assert clipboard_menu.wait(timeout=10) == 0
    eventually(lambda: subprocess.check_output([programs["xclip"], "-selection", "clipboard", "-o"], timeout=3).decode().strip() == clipboard_fixture, "Rofi Clipboard did not restore the intended X11 selection")

    # Power preview uses the production theme and five fixed labels directly.
    # Neither the guarded wrapper nor a power/session command is run here.
    time.sleep(0.3)  # match the wrapper backdrop delay after the previous menu
    power_rows = "".join(f"{entry['label']}\0icon\x1f{programs['powerIcons']}/{entry['label']}.svg\n" for entry in json.loads(Path(programs["powerEntries"]).read_text()))
    power = start("power-preview", [programs["rofi"], "-no-config", "-dpi", str(m["x11Dpi"]), "-dmenu", "-no-custom", "-format", "s", "-show-icons", "-theme", programs["powerTheme"]], stdin=subprocess.PIPE, text=True)
    power.stdin.write(power_rows)
    power.stdin.close()
    power.stdin = None
    eventually(lambda: subprocess.run([programs["xdotool"], "search", "--onlyvisible", "--class", "rofi"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0, "Rofi power preview did not map")
    time.sleep(0.6)
    import_root(output / "power.png")
    subprocess.run([programs["xdotool"], "key", "Escape"], check=True)
    assert power.wait(timeout=5) == 1

    assert len(re.findall(r"0x[0-9a-f]+", root_prop("_NET_CLIENT_LIST"))) >= 3, "desktop needs three sample terminals"
    time.sleep(0.5)
    import_root(output / "desktop.png")

    # Capture only this private X server, then exercise the actual annotation
    # editor and its X11 copy/exit action with the captured public fixture.
    subprocess.run([programs["screenshot"], "screen"], check=True, timeout=15)
    captured = subprocess.check_output([programs["xclip"], "-selection", "clipboard", "-t", "image/png", "-o"], timeout=5)
    assert captured.startswith(b"\x89PNG\r\n\x1a\n"), "X11 screen workflow did not copy PNG"
    satty = start("satty", [programs["satty"], "--filename", str(output / "desktop.png"),
        "--copy-command", programs["xclip"] + " -selection clipboard -t image/png -i",
        "--actions-on-enter", "save-to-clipboard,exit"], env=dict(os.environ, GSK_RENDERER="cairo"))
    eventually(lambda: subprocess.run([programs["xdotool"], "search", "--onlyvisible", "--class", "[Ss]atty"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0, "Satty annotation editor did not map on X11")
    satty_id = subprocess.check_output([programs["xdotool"], "search", "--onlyvisible", "--class", "[Ss]atty"], text=True).splitlines()[-1]
    subprocess.run([programs["xdotool"], "windowactivate", "--sync", satty_id], check=True, timeout=5)
    time.sleep(2.0)
    import_root(output / "annotation.png")
    subprocess.run([programs["xdotool"], "key", "--clearmodifiers", "Return"], check=True)
    assert satty.wait(timeout=10) == 0, "Satty Enter action did not copy and exit"
    annotated = subprocess.check_output([programs["xclip"], "-selection", "clipboard", "-t", "image/png", "-o"], timeout=5)
    assert annotated.startswith(b"\x89PNG\r\n\x1a\n"), "Satty X11 clipboard action failed"

    subprocess.run([programs["notifySend"], "Xorg · One Dark", "隔离显示检查：浮窗、启动器与通知。", "-h", "int:value:63"], check=True)
    time.sleep(0.7)
    import_root(output / "notification.png")
    assert (output / "desktop.png").read_bytes() != (output / "notification.png").read_bytes(), "notification screenshot did not capture the notification"

    # Attempt only the configured lock process on this isolated X server. Never
    # type a password; if PAM blocks mapping, keep the explicit scope result.
    sleep_read, sleep_write = os.pipe()
    lock = start("lock", [programs["lock"]], env=dict(os.environ, XDG_CURRENT_DESKTOP="dwm", XSS_SLEEP_LOCK_FD=str(sleep_write)), pass_fds=(sleep_write,))
    os.close(sleep_write)
    lock_windows = None
    lock_deadline = time.monotonic() + 5
    while time.monotonic() < lock_deadline:
        lock_windows = subprocess.run([programs["xdotool"], "search", "--onlyvisible", "--class", "i3lock"], capture_output=True, text=True)
        if lock_windows.returncode == 0 or lock.poll() is not None:
            break
        time.sleep(0.1)
    assert lock_windows is not None
    if lock_windows.returncode == 0:
        assert select.select([sleep_read], [], [], 2)[0], "locker did not release inherited sleep inhibitor after mapping"
        assert os.read(sleep_read, 1) == b"", "sleep FD must close, not carry data"
        time.sleep(1.0)  # locker maps before Cairo first frame
        import_root(output / "lock.png")
        (output / "lock-scope.txt").write_text("Production lock wrapper mapped on isolated Xvfb; no password entered.\n")
    else:
        (output / "lock-scope.txt").write_text("Production lock wrapper was attempted on isolated Xvfb but did not map (likely PAM/Xvfb limitation); no password entered.\n")
    os.close(sleep_read)
    if lock.poll() is None:
        lock.terminate()
        lock.wait(timeout=5)

    assert picom.poll() is None, "Picom exited during the tray/editor/lock tests"
    (output / "geometry.json").write_text(json.dumps({"single": single, "tiled": tiled, "dialog": g, "launcher": launcher_geometry}, indent=2))
    (output / "scope.txt").write_text("Real dwm + Rofi + status + patched Dunst + Picom XRender under isolated Xvfb at 2560x1600, DPI 144. No real Xorg/GLX/PAM/password/capture acceptance.\n")
finally:
    x.XCloseDisplay(display)
    for child in reversed(children):
        if child.poll() is None:
            child.terminate()
    for child in reversed(children):
        try:
            child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            child.kill()
            child.wait()
    for stream in streams:
        stream.close()
