"""Split uosc 5.12's shared foreground fill from selection surfaces.

Keep icons and progress readable while menu/control selection uses the palette's
neutral surface. Fail on upstream layout changes instead of silently skipping.
"""
from pathlib import Path
import sys

root = Path(sys.argv[1])


def replace(file, old, new, count=1):
    path = root / file
    text = path.read_text()
    assert text.count(old) == count, (file, old, text.count(old))
    path.write_text(text.replace(old, new))


replace("elements/Menu.lua", "local font_color = item.active and fgt or bgt", "local font_color = bgt", 3)
replace("elements/Menu.lua", "color = fg,\n\t\t\t\t\topacity = highlight_opacity * menu_opacity,", "color = config.color.selection,\n\t\t\t\t\topacity = highlight_opacity * menu_opacity,")
replace(
    "elements/Menu.lua",
    "\t\t\tend\n\n\t\t\tlocal title_clip_bx = content_bx",
    "\t\t\tend\n\t\t\tif is_selected then\n\t\t\t\tass:rect(content_rect.ax, item_ay, content_rect.ax + 2, item_by, {\n\t\t\t\t\tradius = 1, color = config.color.match, opacity = menu_opacity, clip = item_clip,\n\t\t\t\t})\n\t\t\tend\n\n\t\t\tlocal title_clip_bx = content_bx",
)
replace("elements/Button.lua", "local foreground = self.active and self.background or self.foreground", "local foreground = self.active and config.color.match or self.foreground")
replace("elements/Button.lua", "local background = self.active and self.foreground or self.background", "local background = self.active and config.color.selection or self.background")
replace("elements/Button.lua", "color = (self.active or not is_hover) and background or foreground,", "color = (self.active or is_hover) and config.color.selection or background,")
replace("elements/TopBar.lua", "local opts = {size = self.font_size, wrap = 2, color = fgt, opacity = visibility}", "local opts = {size = self.font_size, wrap = 2, color = bgt, opacity = visibility}")
replace("elements/TopBar.lua", "color = fg, opacity = visibility * opacity, radius = state.radius,", "color = config.color.selection, opacity = visibility * opacity, radius = state.radius,")
# Remove the upstream close button's private red/white colors as well.
path = root / "elements/TopBar.lua"
lines = path.read_text().splitlines(keepends=True)
matched = 0
for i, line in enumerate(lines):
    if "local close = {icon = 'close', hover_bg =" in line:
        lines[i] = "\tlocal close = {icon = 'close', hover_bg = config.color.selection, hover_fg = config.color.error, command = function() mp.command('quit') end}\n"
        matched += 1
assert matched == 1
path.write_text("".join(lines))
replace("elements/TopBar.lua", "local button_fg = is_hover and (button.hover_fg or bg) or fg", "local button_fg = is_hover and (button.hover_fg or config.color.match) or fg")
replace("elements/TopBar.lua", "local button_bg = is_hover and (button.hover_bg or fg) or bg", "local button_bg = is_hover and (button.hover_bg or config.color.selection) or bg")
