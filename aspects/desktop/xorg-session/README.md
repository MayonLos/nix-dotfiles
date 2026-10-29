# Xorg dwm session

Optional real Xorg for native QQ / Tencent Meeting / OBS capture. Mango remains
the greeter default. The sessions are alternatives; the supervisor rejects an
active Mango or graphical target and takes a process lock before importing any
activation environment. No independent Home Manager switch is supported.

Inputs: user appearance palette (including reduced motion), host X11 DPI, shared
session support and public workspace tool commands. Host support is delivered by
`xorg-session-host`. Only this host aspect enables Xorg/startx, PAM and the unique
`xorg-dwm.desktop` entry. It does not choose an NVIDIA-only desktop or install a
second unconfigured dwm entry.

Public exports: `dwm/package.nix` is a package factory accepting `pkgs`, `palette`,
`profileDirectory`, optional `lib` and `x11Dpi`. `checks.nix` is the explicitly
registered `{ pkgs, lib, system, nixos, home, appearance }` test hook (as needed).
Other Nix files and resources are private.

## Components and ownership

- Pinned dwm-flexipatch, barmodules + status2d + systray. The clock gets the first,
  centered allocation; titles and metrics occupy separately clipped halves.
  The 30 logical px bar has Picom corners, subtle separators, tag underlines,
  occupancy dots and urgent red lines. A small local C module supplies exact
  title/class regex rules, passive mapping and pointer-enter behavior, directional movement, tag following
  and reversible maximize. `dwm/keybindings.json` and `window-rules.json` are the
  sole binding/rule tables; the built package installs copies under `share/dwm`.
- Rofi 2.0 owns Apps / Run / Windows / Clipboard, desktop controls and the five
  power tiles. Rasi takes device pixels, fonts take points; geometry scales once
  from host DPI. Colors come from appearance. Empty input shows a short search
  hint with its caret hidden. Managed NoDisplay desktop overrides hide Rofi's
  own launcher/theme-selector entries; they do not affect CLI commands or history.
  No dmenu or j4 package remains.
- Picom 13 owns 10 logical px corners, soft shadows, 6% inactive dim and <=100ms
  fades. Games/fullscreen/lock exclude effects; reduced motion disables fades.
  dwm owns the 2 logical px blue X border.
- Patched Dunst 1.13 retains a neutral outline and draws a 2 logical px urgency
  strip on the left. Progress/volume/brightness use native notification hints.
  Its D-Bus activation goes through the guarded systemd unit.
- i3lock-color consumes the current Xorg wallpaper record and creates a dark
  cache at runtime, retaining `--nofork` and xss-lock's delay FD protocol. Public
  default is wallpaper-005. Local pictures never become Nix inputs.
- CopyQ owns X11 clipboard history; no database is managed or removed. Rofi's
  clipboard mode verifies an index plus full MIME digest and atomically selects
  the unchanged item. It lists up to 40 items of at most 4 MiB each; the native
  CopyQ tray/history remains available for other items.
  The Mango Wayland/X11 bridge remains Mango-only: a pure Xorg desktop has one
  native selection domain and no Wayland peer to bridge.
- Wallpaper rotation reads `~/Pictures/Wallpapers/{managed,local}` recursively,
  deduplicating symlink targets and cycles. Mango remains the sole writer of the
  managed link and missing local directory. Xorg can also run alone using the
  public store collection as a fallback. Startup uses 005, daily/random-next
  updates its private runtime record; it never edits Noctalia state.
- RandR output events enable preferred modes, place the internal output first
  and new outputs to its right, disable disconnected outputs, and let dwm
  redistribute clients. No output names/EDIDs are hard-coded or profiles saved.

HM owns `rofi/{config,launcher,power}.rasi`, `rofi/power-icons`, the two
NoDisplay entries under `applications/rofi*.desktop`, Picom/Dunst configuration, the
supervisor data entry, helper commands and Xorg user units. Runtime files under
`$XDG_RUNTIME_DIR/nix-dotfiles-xorg` belong only to this session; the wallpaper
cache under `$XDG_CACHE_HOME/nix-dotfiles/xorg-lock` is generated runtime data.
App login data, screenshots, CopyQ/Rofi histories, local images and Xauthority
remain application/user data and survive removal.

## Lifecycle and operation

Picom, Dunst, CopyQ, polkit, status, wallpaper, output watcher, idle and xss-lock
all require `xorg-session.target` and `XDG_CURRENT_DESKTOP=dwm`. Fcitx, xrdb and
PipeWire sockets use the shared public session-target contract. Idle timings
match Mango: lock at 900s, display off at 1800s, suspend at 3600s; xidlehook timers
are cumulative. Fullscreen inhibits these automatic timers. xss-lock retains
lock-before-sleep independently of idle/caffeine. Super+Shift+A toggles the Xorg
idle unit; it does not inhibit a lid-triggered or explicit system suspend.

Super+Return/B/E, Alt+Space, Super+V, HJKL/arrows, Space, Shift+F, Z, numeric
workspace keys, named scratchpads and media keys follow Mango. Full comparison
and deliberate differences are in [the session guide](../../../docs/xorg-desktop-execution.md).
Super+F1 displays help generated from the same binding data.

Print uses slop/maim then Satty for annotate/copy/save; Ctrl+Print directly copies
the X desktop. Super+Print and Super+Shift+Print perform region/desktop OCR.
Mango's scrolling capture and mark-shot pin surface require Wayland and are not
bound to a misleading X11 command. Screenshots are never captured at login or
for the locker background.

Build checks exercise lifecycle failures, production bindings, real dwm geometry,
Rofi selection/cancellation, patched Dunst/Picom XRender, status and image/output
helpers on private Xvfb/D-Bus instances. They do not establish real Xorg GLX,
PAM authentication, mixed-DPI hotplug, suspend/resume or proprietary capture.
Removing this feature withdraws its declarations on the next activation and
retains user data; this implementation task does not activate a generation.

Round 37 keeps Dunst for Xorg, with one canonical `org.freedesktop.Notifications.service` in its tailored package. It activates the guarded `dunst.service`; the redundant Home Manager service file is disabled. Mango continues to use Noctalia notifications. Settings now routes to GTK, and the legacy PipeWire X11 system bell is disabled by shared audio support.
