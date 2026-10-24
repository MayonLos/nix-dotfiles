"""Regression fixtures against the generated rule table, after Mango -p validation."""
import re
import sys
from pathlib import Path

rules = []
for line in Path(sys.argv[1]).read_text().splitlines():
    if line.split("=", 1)[0].strip() != "window_rule":
        continue
    assert len(line.split("=", 1)[1].encode()) <= 255, line
    row = dict(field.strip().split(":", 1) for field in line.split("=", 1)[1].strip().split(","))
    for key in ("app_id", "title"):
        if key in row:
            re.compile(row[key])
    rules.append(row)
assert rules


def resolve(app, title):
    result = {}
    for row in rules:
        if all(key not in row or re.search(row[key], value) for key, value in (("app_id", app), ("title", title))):
            result.update(row)
    return result


for app, title in (
    ("xdg-desktop-portal-gtk", "Open File"),
    ("pinentry-qt", "Please enter your passphrase"),
    ("polkit-gnome-authentication-agent-1", "Authentication Required"),
    ("firefox", "File Upload"),
    ("mpv", "video.mkv"),
    ("imv", "image.png"),
    ("swayimg", "image.png"),
    ("org.pulseaudio.pavucontrol", "Volume Control"),
    ("blueman-manager", "Bluetooth Devices"),
    ("nm-connection-editor", "Network Connections"),
    ("org.gnome.Calculator", "Calculator"),
    ("org.gnome.Gcolor3", "Color Picker"),
    ("mark-shot", "Annotation"),
    ("PrismLauncher", "Edit Instance"),
):
    assert resolve(app, title).get("is_floating") == "1", (app, title)

pip = resolve("firefox", "Picture-in-Picture")
for field in ("is_floating", "is_global", "is_overlay", "is_open_silent"):
    assert pip[field] == "1", (field, pip)
assert float(pip["width"]) / float(pip["height"]) == 16 / 9
assert int(pip["offset_x"]) > 0 and int(pip["offset_y"]) > 0
assert "no_size_hint" not in pip

for app in ("QQ", "wechat", "vesktop", "discord", "wemeetapp"):
    for title in ("Notification", "Sharing Toolbar"):
        row = resolve(app, title)
        assert row["is_open_silent"] == row["is_tag_silent"] == row["is_floating"] == "1", (app, title)
    assert "is_open_silent" not in resolve(app, "Main Chat"), app

for app in ("steam_app_730", "Minecraft 1.21"):
    row = resolve(app, "Game")
    for field in ("no_border", "no_shadow", "no_radius", "no_animation", "force_tearing"):
        assert row[field] == "1", (app, row)
    assert "is_fullscreen" not in row  # do not fullscreen a helper/error dialog
assert resolve("kitty", "terminal")["force_tearing"] == "0"
assert "is_floating" not in resolve("firefox", "Save As - documentation — Mozilla Firefox")
assert "is_floating" not in resolve("kitty", "File Upload")
assert all("tags" not in row for row in rules), "app destinations must remain opt-in"
print(f"window rules: {len(rules)} parsed, application and false-positive fixtures passed")
