---
name: desktop-apps
description: GTK/Qt/font theming, default applications, and the desktop apps this host packages by hand — Thunar and its custom actions, mpv, zathura, Zen browser, QQ/WeChat. Use when an app ignores the dark theme or comes up in default light Fusion, when adding or changing a font, when changing which program opens a file type, when adding a Thunar right-click action, when a config file an app rewrites at runtime fights Home Manager, or when a theme change does not reach one application.
---

# Theming and desktop applications

## Three theming surfaces, one palette

noctalia owns the live palette and renders it into per-application files through
its template system (`modules/home/wm/mango/noctalia.nix`): builtin templates for
btop, cava, **foot, gtk3, gtk4, mango, qt**, community ones for obsidian, vscode,
yazi, **zathura, zen-browser**. Changing the theme is a runtime action, not a
rebuild.

The Nix modules only set up what those templates cannot:

- **GTK** (`modules/home/base/gtk.nix`) — `gtk4.theme = null` on purpose, so
  libadwaita stays unthemed and reads noctalia's generated
  `~/.config/gtk-4.0/gtk.css`. GTK3 uses `adw-gtk3-dark`, which is the theme
  noctalia's gtk3 template is written to recolor; Adwaita-dark does not pick up
  those `@define-color` overrides cleanly. Icons are Papirus-Dark, cursor is
  Bibata-Modern-Ice at 24 (also set in mango's `cursor_theme`/`cursor_size` and in the greeter).
  `dconf` sets `color-scheme = prefer-dark`. **nwg-look is unnecessary** — all of
  this is declarative.
- **Qt** (`modules/home/base/qt.nix`) — mango's `env=` lines set
  `QT_QPA_PLATFORMTHEME=qt6ct` and noctalia renders the palette to
  `~/.config/qt6ct/colors/noctalia.conf`, but qt6ct ignores it without its own
  `qt6ct.conf` naming that palette. That file is seeded (see below). This is why
  Qt file dialogs used to come up in flat light-grey Fusion.
- **Fonts** (`modules/system/user/fonts.nix`) — JetBrainsMono Nerd Font as
  monospace, Noto CJK SC as sans/serif, Noto Color Emoji. `nerd-fonts.symbols-only`
  is listed *in addition* because nerd-icons (and doom-modeline through it) looks
  up the family "Symbols Nerd Font Mono" **by name** and does not fall back to the
  patched JetBrainsMono.

## The seeded-mutable-file pattern

Several apps rewrite their own config, or refuse to start when an `include`
target is missing. Both cases break a read-only `home.file` symlink, so the
pattern here is an activation script that creates the file **only when absent**:

```nix
home.activation.seedX = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
  if [ ! -e "$target" ]; then run install -m 0644 … "$target"; fi
'';
```

Used by foot (`themes/noctalia`), qt6ct (`qt6ct.conf`), zathura (`noctaliarc`)
and Zen (`userChrome.css` / `userContent.css`). The file stays mutable: noctalia
overwrites it on every theme change, and whatever you tweak in qt6ct's GUI
survives.

Decide by ownership: **Home Manager owns it and nothing else writes it →
`home.file`. Something else writes it → seed it.** The third case, where a module
must own a file an app also rewrites, needs `force = true`, because
`backupFileExtension = "backup"` otherwise leaves a stale `.backup` in the way
and takes `home-manager-mayon.service` down at the next activation — see
`editors-ide` on ZCode.

## Default applications

`xdg.mimeApps` in `modules/home/base/xdg.nix`: directories →
Thunar, PDF → zathura, video → mpv, http(s)/html → `zen-beta.desktop`, and plain
text / markdown / shell scripts → `code.desktop` (VS Code, not nvim — nvim is
`EDITOR`, this is the graphical double-click path).

`xdg.enable` itself is false on this host, so `xdg.desktopEntries` emits nothing;
a desktop entry has to be written through `home.file` (`ai-agents.nix` does).

## Thunar

`modules/system/programs/thunar.nix` carries the parts that must be system-level:
the archive and volman plugins, plus gvfs, tumbler (thumbnails), udisks2, xfconf
and dconf. Thumbnails or removable-media mounting breaking usually means one of
those services, not Thunar.

Two Home Manager modules extend it:

- `thunar-terminal.nix` — "Open Terminal Here" goes through
  `~/.local/bin/thunar-open-terminal` (execs foot), registered in
  `~/.config/xfce4/helpers.rc`.
- `thunar-actions.nix` — owns `~/.config/Thunar/uca.xml`, so **the "Configure
  custom actions" dialog can no longer save**; new right-click actions are added
  in that file. Its `accels.scm` counterpart is rewritten by Thunar on exit, so
  the keyboard accel is patched in by an activation script instead of symlinked.

The "Copy as Image" action exists because Thunar's Ctrl+C only ever puts file
*references* on the clipboard — that is GTK file-manager design. The script
normalises to PNG (first frame only) and writes **both** `wl-copy` and `xclip`,
because xwayland-satellite's bridge needs keyboard focus to see the Wayland
selection. See `desktop-mango` for the clipboard bridge story.

## mpv, zathura, Zen

- **mpv** — `gpu-next` on Vulkan with `hwdec = nvdec-copy`, and Anime4K v4.0.1
  shaders fetched by hash into `xdg.configFile."mpv/shaders"`. `Ctrl+1` enables
  the Mode A shader chain, `Ctrl+0` clears it. Changing the shader set means
  editing both `glsl-shaders` and the `CTRL+1` binding — they duplicate the same
  list.
- **zathura** — `include noctaliarc` plus synctex wired for LaTeX
  (`ctrl` + click jumps to the source line); the recolor colours in `options` are
  the fallback when noctalia has not rendered its theme.
- **Zen browser** — from the `zen-browser` flake input (not nixpkgs), with
  `toolkit.legacyUserProfileCustomizations.stylesheets = true`, which is what
  makes the seeded `userChrome.css` / `userContent.css` take effect.

## QQ and WeChat

`modules/home/programs/apps/im.nix`, both from `pkgs-unstable` because stable
lags them. QQ is wrapped for libpipewire (Wayland screen sharing) and pinned to
`--ozone-platform=wayland`; `wechat-uos` runs on XWayland by its own choice of
`QT_QPA_PLATFORM=xcb`.

Do not change the platform flags without reading `desktop-mango` first — which of
the two is on XWayland determines the whole fcitx5 candidate-window DPI setup,
and the comments inside `input-method.nix` are stale on that point.

## QQ / Tencent Meeting screen sharing: X11-only, use the virtual camera

Their share pickers cannot see a Wayland desktop and nothing on the compositor
or portal side changes that. Verified 2026-09-10 against `qq-3.2.32`'s binary:

| In the binary | |
|---|---|
| `XQueryTree`, `XGetImage`, `XShmGetImage` | present — the X11 enumerate-and-grab path |
| `zwlr_foreign_toplevel_manager_v1` | absent |
| `ext_foreign_toplevel_list_v1` | absent |
| Wayland globals it names | only `ext_input_manager_v1` / `ext_input_v1` |

`org.freedesktop.portal.ScreenCast` and `SelectSources` *are* in the binary and
look like proof of portal support — they are not. That is Electron's own code
on a path QQ's picker never takes: with the share dialog open,
`xdg-desktop-portal-wlr` logged **zero** requests. Under mango's rootless
Xwayland `XQueryTree` finds nothing, so the picker ends at
"该应用已无法共享，请重新选择".

Things that look like fixes and are not:

- `--enable-features=WebRTCPipeWireCapturer` — that feature name no longer
  exists in Chromium 144; passing it is a no-op. (And Chromium takes the *last*
  `--enable-features` rather than merging, so a second one would drop the
  wrapper's `WaylandWindowDecorations`.)
- the `LD_LIBRARY_PATH` pipewire wrap in `im.nix` — real and worth keeping, but
  it fixes a dlopen, not the picker.
- `xuwd1/wemeet-wayland-screenshare`, the LD_PRELOAD `XShm*` hook — hooks
  exactly the functions QQ uses, but the repo was archived 2025-09 and its
  wlroots black-screen issue is unresolved.

**There is no working native route, and none is configured.** A v4l2loopback
virtual camera (OBS captures through the portal, writes to a loopback node, QQ
picks it from its *camera* dropdown) was built and verified working here on
2026-09-10, then removed on request because it was not going to be used. Do not
re-add `modules/system/desktop/obs.nix` assuming it went missing -- deleting it
was deliberate. The details, if it is ever wanted back:
`devices=1 video_nr=9 card_label="OBS Virtual Camera" exclusive_caps=1`, where
`exclusive_caps` is what makes an Electron app accept the node at all and
`video_nr` stops it racing the real webcam for `/dev/video0`; no `video` group
is needed because v4l2loopback nodes carry udev's `uaccess` tag.

For an actual meeting, use the **web client in a browser**: browser screen
sharing goes through `org.freedesktop.portal.ScreenCast` and works normally
here.

OBS itself *is* installed, as a Home Manager module:
`modules/home/programs/apps/obs-studio.nix`, with three plugins — `wlrobs`
(wlroots screen capture), `obs-vkcapture` (Vulkan/OpenGL game capture, the
counterpart to `gamescope`/MangoHud in the gaming-stack skill) and
`obs-pipewire-audio-capture`. It is the deleted *system* module
(`modules/system/desktop/obs.nix`, v4l2loopback) that must not come back, not
OBS.
