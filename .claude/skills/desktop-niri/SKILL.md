---
name: desktop-niri
description: The niri/Wayland desktop on this host — compositor config, the noctalia shell, xdg portals, screenshot tooling, and fcitx5 input-method DPI. Use when editing keybinds, window rules or animations, when touching noctalia's bar/launcher/lock screen, when a portal misbehaves or dbus logs duplicate-name errors, when screenshot hover rectangles are misaligned, or when the fcitx5 candidate window is the wrong size in any application.
---

# Desktop: niri, noctalia, portals, IME

niri is **not** a flake input — it comes from nixpkgs via `programs.niri.enable`
in `modules/system/desktop/niri.nix`.

## The niri config is one KDL string

`modules/home/wm/niri/config.nix` writes `xdg.configFile."niri/config.kdl"` as a
single KDL string. Keybinds, window rules, animations and the catch-all
shadow/rounded-corner rule all live in that one string. There is no per-section
file to add; edit the string.

## noctalia

Bar, launcher, lock screen, clipboard, session menu and OSD, all quickshell-based
(`modules/home/wm/niri/noctalia.nix`). `noctalia-greeter` is a **separate** flake
input with its own nixpkgs pin, deliberately not `follows`-ed.

Plugins come from the `noctalia-plugins-official` / `noctalia-plugins-community`
inputs as plain source trees (`flake = false`), consumed with `kind = "path"` so
nothing is cloned at startup. An in-tree plugin lives at
`modules/home/wm/niri/_plugins/`, which survives `importDir` only because it
contains no `.nix` file.

Validate config against the noctalia binary, not against upstream's
`example.toml` — the example has been unreliable across v5 schema changes.

## Portals: do not list extraPortals

`xdg.portal.extraPortals` is deliberately **not** set in
`modules/system/desktop/xdg.nix`. `programs.niri.enable` already brings in
xdg-desktop-portal-gnome, and gtk + gnome-keyring follow. Listing them again
duplicated every backend and spammed dbus-broker with "Ignoring duplicate name".

## Screenshot: mark-shot's niri detection is replaced in-tree

`modules/home/programs/apps/screenshot.nix` wraps the package in a `symlinkJoin`
that swaps `mark-shot-window-detection-niri` for
`modules/home/programs/apps/_mark-shot/window-detection-niri`.

Why: upstream's script only recognises waybar and DankMaterialShell panels, so
with a noctalia bar it reserved nothing at the top of the work area, and it
placed the first tile of a column flush with the work area instead of one `gaps`
below it. Every hover rectangle sat 42 logical px too high — cutting off the
bottom of the window and swallowing a strip of the bar above it.

niri 26.04 additionally never fills `tile_pos_in_workspace_view` for *tiled*
windows (only floating ones), so tiled rectangles must be rebuilt from
`pos_in_scrolling_layout` + `tile_size`. The replacement measures the bar's
exclusive zone from the tallest column and mirrors niri's `tiles_origin` /
`compute_new_view_offset`.

`symlinkJoin` rather than `overrideAttrs` so editing the script does not
recompile the whole Qt application.

## fcitx5 candidate window sizing

fcitx5 runs with `waylandFrontend = true`. A client's candidate window is sized
by **which display protocol that client actually speaks**, and the two halves of
classicui are governed by different knobs:

| Client speaks | classicui half | Sized by |
|---|---|---|
| Wayland (text-input-v3) | Wayland | `wp_fractional_scale_v1` — correct with no configuration |
| XWayland (XIM) | X11 | `PerScreenDPI = "False"` + `Xft.dpi = 144` |

**`ForceWaylandDPI` is the wrong knob and was measured to be wrong on
2026-08-21.** classicui already multiplies by the fractional scale on Wayland,
so forcing 144 renders the popup at 144 × 1.5 — every native client's candidate
window grew by half again — and it cannot reach an X client at all.

The X11 path needs both halves:

- `PerScreenDPI = "False"` in `modules/home/base/input-method.nix`. At its `True`
  default fcitx5 derives DPI from what Xwayland reports for the screen
  (2560×1600 in 677×423 mm → 96) and ignores `Xft.dpi` entirely.
- `Xft.dpi = 144` delivered by the `xrdb-merge` service in
  `modules/home/base/xresources.nix`. Home Manager's own `xrdb -merge` only runs
  when `DISPLAY` is set in the activation environment, which it never is under
  `nixos-rebuild`, and its other path (`xsession.profileExtra`) belongs to startx
  and niri does not source it. Without the service the resource database is
  empty — `xrdb -query` prints nothing.

X pixels under xwayland-satellite are physical pixels (the X server runs at the
output's real scale and nothing scales the client afterwards), so every X client
must be told 96 × 1.5 = 144 itself.

**Which client is on XWayland has changed — do not trust the older comments.**
`modules/home/programs/apps/im.nix` pins QQ to `--ozone-platform=wayland`
(nixpkgs' wrapper passed `--ozone-platform-hint=auto`, which was resolving to
X11); verified 2026-08-21, QQ now holds *zero* connections to
`@/tmp/.X11-unix/X0` and its input goes through text-input-v3. **`wechat-uos` is
the XWayland client now** — it pins `QT_QPA_PLATFORM=xcb`, and `Xft.dpi = 144` is
what keeps it readable. The comments in `input-method.nix` and `xresources.nix`
still describe QQ as the X client; they predate the `im.nix` fix and are stale on
that point. Their reasoning about the knobs is still correct.

Measure before and after with `xwininfo -root -tree | grep -i fcitx` (the window
is named `Fcitx5 Input Window`) and confirm the protocol with
`xlsclients` / `ss -xp`.

## XWayland clipboard

xwayland-satellite 0.8.1/0.8.2 transferred 0 bytes in both directions, so
`modules/home/services/clipboard.nix` bridges it manually. Do not assume the
satellite handles it.
