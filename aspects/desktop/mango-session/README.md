# Mango session

Selectable Mango Wayland desktop. It bundles the compositor configuration, the
independent desktop components, per-session environment, clipboard bridges,
screenshots/OCR, and the host-side Mango/portal modules. It does not select the
login greeter; greeter is a separate feature.

## Inputs and outputs

Inputs are `user.appearance` (palette, fonts, cursor, icon theme,
`reducedMotion`), host display/GPU facts, and the public
`nixDotfiles.graphicalSessionTargets` option from `desktop/session-support`.

Outputs are:

- `~/.config/mango/config.conf`, its keybind help and the append-only
  `keys-mayon/bindings.json` export;
- mangobar (`~/.config/mangobar/`), fuzzel, mako and swayosd configuration and
  their `mango-session.target` user units;
- sweetbg wallpaper daemon, the Matuwall picker and the
  `~/Pictures/Wallpapers/managed` link farm;
- swaylock manual lock, with swayidle locking before sleep;
- Wayland/X11 clipboard bridge, cliphist watchers and wl-clip-persist;
- screenshot and OCR tools;
- host-side `programs.mango`, portal routing and the swayosd libinput backend.

`default.nix` is the public aspect entry. `mango.nix`, `shell.nix`,
`wallpaper.nix`, `lock.nix`, `clipboard.nix`, `screenshot.nix`,
`tesseract-ocr.nix`, `session-environment.nix`, `mango/`, `resources/` and
`host/` are private implementation. `checks.nix` is the explicit public test
hook.

## Top bar

mangobar draws a 30 logical px bar, flush and fully transparent: it paints no
background and Mango does not blur its layer, so the wallpaper shows through.
Left to right: Mango's `layout_symbol`, workspace numbers with `hide-empty`,
the minimized-client count (`hideclients`, omitted while the count is 0), the
focused client title from Mango IPC (truncated at 300 px), the StatusNotifier
tray, `CPU {usage}%`, `MEM {}%`, a network glyph, battery glyph plus percent and
one clock `{:L%m月%d日 周%a %H:%M}` under `LC_TIME=zh_CN.UTF-8`. `{usage}` is the
`/proc/stat` percentage sampled at 2 s; memory `{}` is
`(MemTotal-MemAvailable)/MemTotal`. `{load}` is the 1-minute load average and
is not shown. There is no Bluetooth readout, launcher button, unread bell,
control-center button, volume or brightness readout. Font is `Maple Mono NF CN`
Medium 13px; the active workspace is blue without an underline. CPU, memory and
the minimized count use CSS `#cpu`, `#mem` and `#hideclients`.

The StatusNotifier tray draws its own DBusMenu popups, so the same stylesheet
themes them: `menu`, `menuitem`, `menuitem:hover` and a local
`menuitem-disabled.patch` give One Dark surface/border, hover fill and a muted
disabled colour. That one stylesheet is the global entry point, so every SNI
application's right-click menu is themed. Bluetooth hardware policy stays in
the Legion feature; the bar does not poll BlueZ.

The Neovim desktop entry (`kitty --class=Neovim nvim`) is generated here so the
tray/window identity is explicit.

## Launcher, notifications, OSD

`Alt+Space` runs `fuzzel --no-icons`; it is the only launcher (60 columns,
centered, palette colors). The ini leaves icons enabled because `Super+V` uses
fuzzel's dmenu image protocol. Pinned Mango keeps `enable_hotarea` at its
default of 0; turning it on opens the overview, not the launcher. There is no
dock, control center or desktop notification history.

mako owns `org.freedesktop.Notifications`: top-right, width 360, opaque surface,
1 px border, at most 3 visible, `outer-margin = "42,28,0,0"` so the first card
clears the bar. Its package removes the upstream mis-named D-Bus service file
and installs `org.freedesktop.Notifications.service` with
`SystemdService=mako.service`. Each opened notification plays the freedesktop
message sound through `pw-play`; failures are ignored.

swayosd draws volume/brightness OSDs: compact pill (`#container` inset
`8px 14px`, 13 px labels, 18 px icons, 4 px progress rail), `top_margin =
(logicalHeight - 96 - 26) / logicalHeight`. Volume, brightness and microphone
keys all call `swayosd-client` (including `--input-volume mute-toggle`); media
keys call playerctl. A root `swayosd-libinput-backend` service watches
Caps/Num/Scroll and publishes them on the system bus. Brightness writes need the
package udev rules and the `video` group (applies on next login).

## Wallpaper

Mango itself has no wallpaper renderer. One `sweetbgd` session daemon owns the
layer surface; Home Manager renders `~/.config/sweetbg/config.toml` with the
factory image, palette background and `cover` mode. `~/Pictures/Wallpapers/managed`
is a HM link farm of the 18 bundled images; activation only creates a missing
`local/` directory for user images and never rewrites either side. `Super+W`
runs `wallpaper-pick`, which opens Matuwall on those two directories. Its
command backend calls `wallpaper-apply <path>`, the single apply path: it
validates the file, writes `~/.local/state/mango-session/wallpaper`, and sends
`sweetbg img` over the daemon socket instead of restarting a process. The
daemon's `ExecStartPost` restores that state after every start; a missing or
invalid state file leaves the factory default `wallpaper-005.png`. The greeter
and the lock screen keep that factory default and do not read the state file.
The local Matuwall patch follows symlinked directories because `managed/` is a
link farm.

## Lock and idle

Mango implements `ext-session-lock-v1`, so standalone `swaylock` owns the lock
surface. `Super+Alt+L` locks on demand. Host-side
`security.pam.services.swaylock` makes unlocking possible. `swayidle` (bound to
`mango-session.target`) has no idle timeouts: nothing locks or suspends from
inactivity. It only locks before a logind sleep request, such as a lid close or
a manual suspend. Automatic screen-off is not emulated; there is no
DND/caffeine switch.

## Clipboard

`clipboard-bridge` synchronizes the Wayland and X11 selections because Mango's
Xwayland does not. cliphist watchers (text and images) and wl-clip-persist keep
history. `Super+V` runs `clipboard-history`, which opens `cliphist-tui` in a
floating Kitty window (`app_id` `cliphist-tui`, 0.78 by 0.78). Images are
drawn with the Kitty graphics protocol, not as fuzzel row icons. Enter copies
the entry with `wl-copy` and records `CT_COPY_MARK`; the local patch stops
upstream from deleting that cliphist row. Escape leaves the mark empty. The
focused `appid` is read with `mmsg get focusing-client` before Kitty takes the
seat. After a short pause, `paste-key` sends evdev `KEY_V` (47) with Ctrl, plus
Shift for kitty, Alacritty, foot, wezterm, ghostty and the GNOME/xterm ids, and
Ctrl alone otherwise. It uploads a normal evdev keymap first, because wlroots
rejects modifiers until that request. `wtype` is not used: its `-k`
mapping is keycode 1, which this Mango reads as Escape, so Ctrl+Shift+V opened
the btop scratchpad. Image rows are not typed into those terminals. `paste-key`
failures leave the copied bytes in place. Inside the TUI, `Ctrl-X` deletes one
row and `Alt+X` wipes the database. The TUI's `wl-paste --watch` only reloads
the open list. Preview files live in `~/.cache/cliphist-tui` and can be deleted. There is no second
launcher. The cliphist database is not deleted or moved by configuration.

## Screenshots and OCR

`Print` runs mark-shot, `Ctrl+Print` copies the current screen and
`Shift+Print` runs mark-shot's scrolling mode. `Super+Print` OCRs a selection
and `Super+Shift+Print` OCRs the whole desktop; both use the local Tesseract
data and exit quietly when cancelled.

## Session services

All desktop units are `PartOf`/`After`/`WantedBy` `mango-session.target`:
mangobar, mako, swayosd, sweetbgd, swayidle and the session polkit agent
(`polkit-gnome-authentication-agent-1`). Clipboard units run on the same
target. Mango itself starts the target from its C startup path; HM's non-empty
`autostart_sh = ":"` keeps the synchronization hook active without being the
only startup path. Service lifecycle details are in
[service-policy.md](../../../docs/service-policy.md).

Mango is exec'd from the session desktop file, not a login shell, so the module
copies a filtered whitelist of `systemd.user.sessionVariables` into Mango's
`env` rows (`session-environment.nix` drops values needing shell expansion,
secrets and over-long rows). Dynamic `DISPLAY`/`WAYLAND_DISPLAY`/cursor
variables are imported by Mango.

## Window rules

The only rule table is `mango/window-rules.nix`. Rules apply in order; when
`app_id` and `title` are both present they are AND-ed, and titles are matched at
map time. Normal clients tile. Dialogs, progress/preferences/bulk-rename
windows, polkit/pinentry prompts and small standalone tools float at fixed
proportions. Audio/Bluetooth/network tools and calculators share one centered
`tools` size. Viewers and named TUI scratchpads use a workspace-sized surface.
Firefox PiP floats at its own 480×270 size with offsets and stays out of the way.
Games (`steam_app_*`, Minecraft) opt into tearing and lose border/shadow/radius.
`mango/check-window-rules.py` drives representative app IDs/titles through the
generated config and asserts the resulting geometry.

## Mango visual settings

2 px border, 16 px radius, 10/16 px inner/outer gaps with `smart_gaps = 0` so a
single tiled window keeps the frame; only monocle drops its frame. Floating
clients get a soft shadow (size 18, blur 32, offset y 10). Inactive clients dim
at `0x18` while staying opaque; fullscreen is exempt. Open/close zoom between
0.92 and 1 over 220/180 ms, tag changes slide in 280 ms, focus interpolates
border and dim in 120 ms. `reducedMotion` disables animation. Native layer blur
is on only for the bar/notification/OSD layers declared in `layer_rule`; all
other layers and normal windows stay unblurred.

## Checks and removal

`mango-blur-sampling` builds the patched compositor and checks the blur sampler;
`interactive-session-config` parses the generated Mango config with the real
binary, validates the window rules, fonts, avatar hand-off, wallpaper activation,
session units and the bar/mako/swayosd/fuzzel contract. Neither starts a
compositor or connects to a real session.

Removing the selection withdraws the generated configuration and session units
on the next activation. It preserves user state: cliphist database, scrollback,
screenshots, `Pictures/Wallpapers/local/`, `~/.face`, and AccountsService files.
No build or check switches or stops the running session.
