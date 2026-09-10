---
name: desktop-apps
description: GTK/Qt/font theming, default applications, and the desktop apps this host packages by hand — Thunar and its custom actions, mpv, zathura, Zen browser, QQ/WeChat. Use when an app ignores the dark theme or comes up in default light Fusion, when adding or changing a font, when changing which program opens a file type, when adding a Thunar right-click action, when a config file an app rewrites at runtime fights Home Manager, or when a theme change does not reach one application.
---

# Theming and desktop applications

## Three theming surfaces, one palette

noctalia owns the live palette and renders it into per-application files through
its template system (`modules/home/wm/niri/noctalia.nix`): builtin templates for
btop, cava, **foot, gtk3, gtk4, niri, qt**, community ones for obsidian, vscode,
yazi, **zathura, zen-browser**. Changing the theme is a runtime action, not a
rebuild.

The Nix modules only set up what those templates cannot:

- **GTK** (`modules/home/base/gtk.nix`) — `gtk4.theme = null` on purpose, so
  libadwaita stays unthemed and reads noctalia's generated
  `~/.config/gtk-4.0/gtk.css`. GTK3 uses `adw-gtk3-dark`, which is the theme
  noctalia's gtk3 template is written to recolor; Adwaita-dark does not pick up
  those `@define-color` overrides cleanly. Icons are Papirus-Dark, cursor is
  Bibata-Modern-Ice at 24 (also set in niri's `cursor` block and in the greeter).
  `dconf` sets `color-scheme = prefer-dark`. **nwg-look is unnecessary** — all of
  this is declarative.
- **Qt** (`modules/home/base/qt.nix`) — niri's `environment` block sets
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
selection. See `desktop-niri` for the clipboard bridge story.

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

Do not change the platform flags without reading `desktop-niri` first — which of
the two is on XWayland determines the whole fcitx5 candidate-window DPI setup,
and the comments inside `input-method.nix` are stale on that point.
