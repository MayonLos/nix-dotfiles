"""Generated-config regression checks, after locked Mango's own -p parser.

Fixtures describe matching policy, not runtime evidence for proprietary apps.
Python re is sufficient for the deliberately shared PCRE/Python subset here.
"""

import re
import sys
from pathlib import Path

# Mango 9c44c664, src/config/option_defs.c:1341-1638. Keep this explicit so an
# accidental Hyprland/Sway field cannot silently enter a generated rule.
WINDOW_FIELDS = set("""
    is_floating title app_id animation_type_open animation_type_close tags monitor
    offset_x offset_y no_focus no_fade_in no_fade_out no_force_center width height
    no_border no_shadow no_radius no_animation is_open_silent is_tag_silent
    is_named_scratchpad is_unmanaged_global is_global scroller_proportion_single
    unfocused_opacity focused_opacity is_overlay shield_when_capture
    allow_shortcuts_inhibit ignore_maximize ignore_minimize no_size_hint
    idle_inhibit_when_focus vrr_only_fullscreen force_render activation_bypass
    is_term allow_csd force_fake_maximize force_tiled_state force_tearing no_swallow
    confine_pointer no_blur scroller_proportion is_fullscreen is_fake_fullscreen
    global_key_binding
""".split())
LAYER_FIELDS = set("""
    layer_name animation_type_open animation_type_close shield_when_capture
    no_blur no_animation no_shadow
""".split())
RULES = []
for line in Path(sys.argv[1]).read_text().splitlines():
    kind, sep, value = line.partition("=")
    if kind.strip() not in ("window_rule", "window_rule_once", "layer_rule") or not sep:
        continue
    assert len(value.encode()) <= 255, line
    pairs = [field.strip().split(":", 1) for field in value.strip().split(",")]
    row = dict(pairs)
    assert len(row) == len(pairs), ("duplicate property", line)
    allowed = LAYER_FIELDS if kind.strip() == "layer_rule" else WINDOW_FIELDS
    assert row.keys() <= allowed, ("unknown field", row.keys() - allowed)
    for key in ("app_id", "title", "layer_name"):
        if key in row:
            re.compile(row[key])
    for key in ("width", "height"):
        if key in row:
            assert float(row[key]) > 0, row
    if kind.strip() != "layer_rule":
        assert "app_id" in row, ("unscoped title rule", row)
        RULES.append(row)
assert RULES


def resolve(app, title):
    result = {}
    for row in RULES:
        if all(key not in row or re.search(row[key], value) for key, value in (("app_id", app), ("title", title))):
            result.update(row)
    return result


# Both observed IDs and explicitly conditional title fallbacks. Do not mistake
# these fixtures for having opened a login-only app's post-login windows.
for app, title in (
    ("firefox", "Library"),
    ("firefox", "About Mozilla Firefox"),
    ("firefox", "Open File"),
    ("firefox", "Save As"),
    ("xdg-desktop-portal-gtk", "Open File"),
    ("org.gtk.GtkFileChooserDialog", "Save File"),
    ("polkit-gnome-authentication-agent-1", "Authentication Required"),
    ("thunar", "File Operation Progress"),
    ("thunar", "Bulk Rename - Rename Multiple Files"),
    ("thunar", "example.txt - Properties"),
    ("thunar", "Thunar Preferences"),
    ("Thunar", "Thunar 首选项"),
    ("org.pulseaudio.pavucontrol", "Volume Control"),
    ("blueman-manager", "Bluetooth Devices"),
    ("org.blueman.Manager", "Bluetooth Devices"),
    (".blueman-manager-wrapped", "Bluetooth Devices"),
    ("nm-connection-editor", "Network Connections"),
    ("com.github.hluk.copyq", "CopyQ"),
    ("qt6ct", "Qt6 Configuration Tool"),
    ("org.gnome.FileRoller", "File Roller"),
    ("kbd-layout-viewer", "Keyboard Layout viewer"),
    ("legion_gui", "LenovoLegionLinux"),
    ("feh", "image.png"),
    ("org.prismlauncher.PrismLauncher", "Prism Launcher Quick Setup — Prism Launcher 11.1.1"),
    ("org.fcitx.", "Fcitx Configuration"),
    ("org.gnome.Calculator", "Calculator"),
    ("steam", "Friends List"),
    ("steam", "Steam Settings"),
    ("QQ", "Image Viewer"),
    ("wechat", "Video Call"),
    ("vesktop", "Vesktop Setup"),
    ("thunderbird", "Preferences"),
    ("code", "Add Folder to Workspace"),
    ("md.obsidian.Obsidian", "Open File"),
    ("Excalidraw", "Save As"),
    ("jetbrains-pycharm", "PyCharm User Agreement"),
    ("jetbrains-clion", "CLion User Agreement"),
    ("jetbrains-idea", "Settings"),
    ("libreoffice-writer", "Save As"),
    ("libreoffice-startcenter", "Welcome to LibreOffice."),
    ("libreoffice-startcenter", "Database Wizard"),
    ("Zotero", "Zotero LibreOffice Integration"),
    ("MATLAB R2026b", "Preferences"),
    ("com.obsproject.Studio", "Settings"),
    ("com.obsproject.Studio", "Auto-Configuration Wizard"),
    ("org.kde.kdenlive", "Open File"),
    ("gimp", "Toolbox"),
    ("Blender", "Preferences"),
    ("virt-manager", "New VM"),
    (".virt-manager-wrapped", "添加连接"),
    ("virt-manager", "QEMU/KVM - Connection Details"),
    (".virt-manager-wrapped", "QEMU/KVM - 连接详情"),
):
    row = resolve(app, title)
    assert row.get("is_floating") == "1", (app, title, row)
    assert "no_force_center" not in row, (app, title, row)

# Protect normal windows and document/tab titles from overly broad community
# snippets (e.g. float all Zotero, Steam or "Save As.*" windows).
for app, title in (
    ("firefox", "Save As - documentation — Mozilla Firefox"),
    ("firefox", "Settings — Mozilla Firefox"),
    ("thunar", "Settings - Thunar"),
    ("kitty", "Settings"),
    ("code", "Settings — project — Visual Studio Code"),
    ("jetbrains-idea", "project – IntelliJ IDEA"),
    ("libreoffice-writer", "Settings.odt — LibreOffice Writer"),
    ("Zotero", "My Library - Zotero"),
    ("QQ", "QQ"),
    ("wechat", "Weixin"),
    ("wemeetapp", "腾讯会议"),
    ("wemeetapp", "Screen Share"),
    ("wemeetapp", "屏幕共享"),
    ("vesktop", "Discord"),
    ("thunderbird", "Home - Mozilla Thunderbird"),
    ("steam", "Steam"),
    ("com.obsproject.Studio", "OBS Studio"),
    ("Blender", "Blender"),
    ("org.pwmt.zathura", "paper.pdf"),
):
    row = resolve(app, title)
    assert "is_floating" not in row, (app, title, row)
    assert "no_focus" not in row and "is_open_silent" not in row, (app, title, row)

for app in ("QQ", "wechat", "vesktop", "discord", "wemeetapp"):
    row = resolve(app, "Sharing Toolbar")
    assert all(row[key] == "1" for key in ("is_floating", "no_focus", "is_open_silent", "is_tag_silent")), row
    assert "no_focus" not in resolve(app, "Video Call"), app

progress = resolve("Thunar", "文件操作进度")
assert (float(progress["width"]), float(progress["height"])) == (0.42, 0.42), progress
agreement = resolve("jetbrains-pycharm", "PyCharm User Agreement")
assert "width" not in agreement and "height" not in agreement, agreement

pip = resolve("firefox", "Picture-in-Picture")
assert all(pip[key] == "1" for key in ("is_floating", "is_global", "is_overlay", "is_open_silent")), pip
assert float(pip["width"]) / float(pip["height"]) == 16 / 9
assert "no_size_hint" not in pip  # keep client hints; no keepaspectratio field exists
for app in ("steam_app_730", "steam_app_0", "Minecraft 1.21"):
    row = resolve(app, "Game")
    assert all(row[key] == "1" for key in ("no_border", "no_shadow", "no_radius", "no_animation", "force_tearing", "vrr_only_fullscreen")), row
    assert "is_fullscreen" not in row
for app in ("steam", "steam_app_helper", "code", "firefox", "mpv", "kitty"):
    assert resolve(app, "main")["force_tearing"] == "0", app
assert resolve("kitty", "terminal")["no_blur"] == "0"
for app in ("mayon-scratch", "mayon-files", "mayon-monitor"):
    row = resolve(app, app)
    assert row["is_named_scratchpad"] == "1" and row["no_blur"] == "0", row
assert all("tags" not in row and "monitor" not in row for row in RULES)
# R52 role sizes and centering are deliberate policies, checked after Mango's parser.
for app, title, size in (
    ("firefox", "Open File", (0.56, 0.64)),
    ("pinentry-qt", "Authentication Required", (0.42, 0.42)),
    ("org.pulseaudio.pavucontrol", "Volume Control", (0.46, 0.58)),
    ("dev.noctalia.Noctalia", "Noctalia Settings", (0.68, 0.78)),
    ("swayimg", "image.png", (0.78, 0.78)),
    ("virt-manager", "Virtual Machine Manager", (0.78, 0.78)),
    (".virt-manager-wrapped", "虚拟系统管理器", (0.78, 0.78)),
):
    row = resolve(app, title)
    assert (float(row["width"]), float(row["height"])) == size, (app, title, row)
    assert not {"offset_x", "offset_y", "no_force_center"} & row.keys(), row
for app in ("mayon-scratch", "mayon-files", "mayon-monitor", "mayon-clash", "mayon-tools", "mayon-bili"):
    row = resolve(app, app)
    assert (float(row["width"]), float(row["height"])) == (0.78, 0.78), row
    assert row["focused_opacity"] == row["unfocused_opacity"] == "1.0", row
    assert row["no_blur"] == "0", row
for app in ("mayon-docker", "mayon-ports", "serial-mayon", "shots-mayon", "keys-mayon"):
    row = resolve(app, app)
    assert "is_named_scratchpad" not in row, (app, row)
print(f"window rule policy: {len(RULES)} rules; valid fields, UTF-8 limits, dialogs, main-window exclusions, PiP, silent toolbar and fullscreen fixtures passed")
