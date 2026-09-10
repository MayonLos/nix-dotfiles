---
name: desktop-mango
description: The mango/Wayland desktop on this host — compositor config, the noctalia shell and greeter, xdg portals, screenshot tooling, clipboard, and fcitx5 input-method DPI. Use when editing keybinds, window rules, tags or animations, when touching noctalia's bar/launcher/lock screen or the login screen, when a portal misbehaves or screen capture fails, when screenshot hover rectangles are wrong, when copy/paste fails between Wayland and X11 clients or clipboard history is empty, or when the fcitx5 candidate window is the wrong size in any application.
---

# Desktop: mango, noctalia, portals, IME

MangoWC is a dwl derivative. Unlike niri before it, mango **is** a flake input
(`mango.url = "github:mangowm/mango"`), deliberately not `follows`-ed: it pins
its own `scenefx`, and mango/scenefx/wlroots are a version-tight triple. There
is no binary cache, but the build is dwl-sized C and takes seconds.

- `modules/system/desktop/mango.nix` — `programs.mango.enable`
- `modules/home/wm/mango/config.nix` — the compositor config
- `modules/home/wm/mango/noctalia.nix` — the shell

`main` is this configuration. The last pure-niri state is commit `6c006fe`,
reachable from history (`git switch -c niri 6c006fe`) but no longer a branch.

## Verify config keys against the source, not the docs site

The upstream docs are incomplete and in places stale — `monitorrule`'s old
positional form is documented in places but rejected by the current parser. The
source is the authority, and it is already in the store:

```sh
SRC=$(nix eval --raw '.#nixosConfigurations.nixos-btw.config.programs.mango.package.src')
grep -w '"blur_params_radius"' "$SRC"/src/config/parse_config.c   # is this a real key
grep -w '"togglemaximizescreen"' "$SRC"/src/config/parse_config.c # is this a real dispatcher
```

`parse_option()` in `src/config/parse_config.c` is one long `strcmp` chain of
every valid key; `parse_func_name()` is the same for dispatchers. An unknown key
is a hard "Unknown keyword" error, not a silent ignore.

## The config is structured Nix, rendered to key=value

### What the build already checks, and what it cannot

The home-manager module runs `mango -c <generated> -p` as a build step, so a
`nixos-rebuild` **fails** on a syntactically bad config. Verified against the
running binary:

| Written | Result |
|---|---|
| `not_a_real_key=3` | build fails — `Unknown keyword: not_a_real_key` |
| `bind=SUPER+grave,toggle_scratchpad` | build fails — `Invalid bind format` |
| `bind=SUPER+CTRL,R,setmfact,0.55` | **builds fine, does nothing at runtime** |

So typos and unknown keys are caught for you. What is never caught is a value
that parses but means something other than it looks like — the `setmfact` case
below is the known one. Check semantics against the source; leave syntax to the
build.


`wayland.windowManager.mango.settings` is a free-form attrset the home-manager
module flattens into `~/.config/mango/config.conf`:

- nested attrs join with underscores — `blur_params = { radius = 5; }` becomes
  `blur_params_radius = 5`. Pick one spelling and stay consistent.
- a config key that legitimately repeats (`bind`, `bindl`, `windowrule`,
  `tagrule`, `monitorrule`) is written as a **list**.
- modal submaps go under `keymode.<name>.bind`. `keymode` only scopes the `bind`
  lines that follow it; other keys are unaffected.
- `extraConfig` is appended verbatim at the very end of the file.

The module emits `key = value` with spaces around the `=` while the docs show
`key=value`. Both parse — `parse_config_line()` trims key and value.

### `systemd.enable` alone starts nothing — `autostart_sh` does

This one failure explains a whole screenful of unrelated-looking symptoms, so
check it first whenever "half the session did not come up".

`wayland.windowManager.mango.systemd.enable` only *defines*
`mango-session.target`. The lines that actually run
`dbus-update-activation-environment --systemd …` and
`systemctl --user start mango-session.target` live in the autostart script the
module generates — and the module writes that script, and appends its
`exec-once=~/.config/mango/autostart.sh`, **only when `autostart_sh` is
non-empty** (`nix/hm-modules.nix`). Autostarting things from an `exec-once` in
`extraConfig` instead leaves `autostart_sh` empty and that whole path never runs.

`graphical-session.target` `BindsTo` mango-session.target, so when the target
never starts, every user unit hanging off it stays dead at once:

| Dead unit | Symptom |
|---|---|
| `fcitx5-daemon` | input method does not autostart |
| `cliphist-watch-text` / `-image` | clipboard history stays empty |
| `xrdb-merge` | `xrdb -query` empty, `Xft.dpi` unset, fcitx5's X11 candidate window mis-sized |

and, because `dbus-update-activation-environment` never ran, D-Bus- and
launcher-started apps never see `NIXOS_OZONE_WL`. The nixpkgs Electron wrappers
add `--ozone-platform=wayland` only when that is set, so Electron apps fall back
to X11 → XWayland, render at the unset (96) DPI, and get upscaled to 1.5 —
**blurry app windows**, which reads as a scaling bug and is not one.

Diagnose with `systemctl --user is-active graphical-session.target` and
`ls ~/.config/mango/autostart.sh`. Everything meant to autostart belongs in
`autostart_sh`, never in an `exec-once` of its own.

### setmfact follows dwm's convention, and gets this wrong silently

`set_master_factor` (`src/dispatch/bind.c`) reads an argument **below 1.0 as a
delta** and only `>= 1.0` as an absolute value, taken as `value - 1.0`. It then
drops anything landing outside `0.1 … 0.9` by returning early.

So `setmfact,0.55` does not set mfact to 0.55 — it adds 0.55 to the current
value, overshoots 0.9, and **does nothing at all, with no error**. To set 0.55
absolutely, write `1.55`. Relative nudges (`+0.05`, `-0.05`) are the normal case
and read naturally.

### A bind line needs at least three comma-separated fields

`sscanf(value, "%255[^,],%255[^,],%255[^,]…") < 3` is rejected as
"Invalid bind format". `"SUPER+grave,toggle_scratchpad"` looks plausible and is
not — the modifier and the key are separate fields:
`"SUPER,grave,toggle_scratchpad"`. Modifiers join with `+` and are lowercased
before matching, so `SUPER+CTRL`, `Alt`, `none` all work.

`bindl` fires while locked; the suffix letters after `bind` are flags
(`l` lock, `r` release, `p` pass, `s` keysym, `c` allow-conflict).

### Layout lives on tagrule, not monitorrule

`mfact`, `nmaster` and `layout_name` are `tagrule` fields. `monitorrule` is
named `key:value` only — resolution is `width` + `height`, refresh is `refresh`,
rotation is `rr`. This host runs one output at `scale:1.5`.

Per-tag layouts are the point of being here: most tags are `tile` (dwm
master-stack), and a couple stay `scroller` for the niri-style workflow.

## mango inherits no session variables — mirror them with `env=`

The session desktop file is `Exec=mango`, executed directly. niri got Home
Manager's session variables because `niri-session` is a shell wrapper that
sources `hm-session-vars.sh`; mango has no such step, so **its process
environment starts nearly empty** (`XDG_SESSION_TYPE`, `XDG_CURRENT_DESKTOP`,
and what it sets itself). Everything mango spawns — noctalia, and every app
noctalia's launcher starts — inherits that.

`modules/home/wm/mango/config.nix` puts them back by mirroring
`config.home.sessionVariables` into `env=` lines, which mango setenv's into its
own process while parsing the config (`src/config/parse_config.c:335`).

The one that bites hardest is `NIXOS_OZONE_WL`: the nixpkgs Electron wrappers
add `--ozone-platform=wayland` only when it is set, so without it every Electron
app silently lands on XWayland and looks **blurry** at this 1.5x scale — which
reads as a compositor scaling bug and is not one. `XMODIFIERS`,
`GLFW_IM_MODULE` and `SDL_IM_MODULE` ride along in the same set, so input method
in launcher-started apps depends on this too.

Two things to know before editing it:

- Values needing shell expansion are filtered out. mango expands `~/` and
  nothing else, so a `${...}` or `$(...)` would be set as that literal string.
- `systemctl --user show-environment` showing a variable proves nothing about
  mango: Home Manager writes `systemd.user.sessionVariables` separately, so the
  systemd/D-Bus environment can look correct while mango's own is missing it.
- **`/proc/$(pgrep -x mango)/environ` proves nothing either**, and reading it as
  if it did wasted a whole debugging round here. That file is the environment
  block as it was at `exec`; the `env=` entries are applied later by `setenv()`
  while mango parses its config, and never appear in it. mango's environ shows
  the bare greetd/PAM set (`EDITOR=nano` and friends) even when everything is
  working. Check a **child** instead — `tr '\0' '\n' < /proc/$(pgrep -x
  noctalia)/environ` — since inheritance is the thing that actually matters.

## noctalia

Bar, launcher, lock screen, clipboard, session menu and OSD, all in
`modules/home/wm/mango/noctalia.nix`. `noctalia-greeter` is a **separate** flake
input with its own nixpkgs pin, deliberately not `follows`-ed.

noctalia has a **first-class mango backend** — `src/compositors/mango/` carries
runtime, workspace, keyboard and output backends, talking mango's IPC socket. So
the built-in `"workspaces"` bar widget shows tags directly; no niri-style
third-party workspace plugin is needed (there was one, `salemsayed/niri-active-workspace`,
and it is gone).

Plugins come from the `noctalia-plugins-official` / `noctalia-plugins-community`
inputs as plain source trees (`flake = false`), consumed with `kind = "path"` so
nothing is cloned at startup. An in-tree plugin lives at
`modules/home/wm/mango/_plugins/`, which survives `importDir` only because it
contains no `.nix` file.

Validate config against the noctalia binary, not against upstream's
`example.toml` — the example has been unreliable across v5 schema changes.

### The theme template is sourced, not included

noctalia's builtin `mango` template (`assets/templates/builtin.toml`) renders the
palette to `$XDG_CONFIG_HOME/mango/noctalia.conf`. The compositor config pulls it
in from `extraConfig`, last, so those colours win:

```
source-optional=/home/mayon/.config/mango/noctalia.conf
```

`source-optional`, not `source`: the file does not exist until noctalia first
applies a theme, and a plain `source` of a missing file is a parse error. niri
needed an activation script to seed an empty file for exactly this reason; mango
has the optional form built in, so there is nothing to seed.

## Portals: add to extraPortals, never replace it

Entries arrive from three different modules and the merged list is correct only
if all of them survive:

| From | Contributes |
|---|---|
| mango's NixOS module | `xdg-desktop-portal-wlr`, `xdg-desktop-portal-gtk` |
| `xdg.portal.wlr.enable` | wlr again |
| `desktop/xdg.nix` | `xdg-desktop-portal-gnome`, `gnome-keyring` |

Duplicates are the *same* derivations and collapse to one store path in the union
that `services.dbus.packages` and `systemd.packages` build from — one service
file, one process, no second claimant for a D-Bus name. **An `mkForce` that
"tidies" the list silently disables whichever backend it forgets.** Add, never
replace.

Two things used to arrive free with `programs.niri.enable` and are now asked for
by name in `desktop/xdg.nix`:

- **`services.gnome.gnome-keyring.enable`** — niri's module set this. It is not
  just a portal: it is the Secret Service every application stores passwords in.
  mango's module routes `org.freedesktop.impl.portal.Secret` at gnome-keyring but
  never enables it, so dropping this line points the Secret portal at a backend
  that is not running.
- **`xdg-desktop-portal-gnome`**, for the file chooser alone.
  `xdg-desktop-portal-gtk` is still GTK 3, which cannot do fractional scaling, so
  on this 1.5x output its file chooser renders at 1x — noticeably smaller text
  than the app that opened it.

**Screen capture must stay on wlr.** niri implemented
`org.gnome.Mutter.ScreenCast`, which is why ScreenCast and Screenshot pointed at
the GNOME backend before. mango is plain wlroots and has no such interface, so
capture goes through `xdg-desktop-portal-wlr`.

### xdpw needs to be told which output, or capture is silently black

Out of the box xdpw asks an external *chooser* which output to capture, and its
default chooser list is dmenu-shaped — bemenu, wmenu, wofi, rofi. None of those
are installed here, so all of them failed and xdpw gave up:

```
xdg-desktop-portal-wlr: /bin/sh: line 1: wofi: command not found
xdg-desktop-portal-wlr: [ERROR] - wlroots: no output found
```

What that reaches the user as is an OBS screen-capture source that stays black,
with nothing in OBS's own log to explain it. **`slurp` does not help** — it
selects a *region*, not an output, and is not in that list.

The fix goes in **`xdg.portal.wlr.settings`** (NixOS), not in a
`~/.config/xdg-desktop-portal-wlr/config`. That NixOS option generates an ini
and the service is launched with `--config=<that ini>`, and xdpw's
`init_config()` skips its own `$XDG_CONFIG_HOME` search entirely once
`--config` is given — so a hand-written user config is silently never read.
Check `ps` for the `--config=` argument before believing any xdpw config file.

`modules/system/desktop/xdg.nix` sets `chooser_type=none` plus
`output_name=eDP-1`: one output, so skip the chooser rather than install a
picker to answer a question with one possible answer. Revisit if a second
output ever appears.

Only keys mango's own module leaves unset may be added to `xdg.portal.config.mango`;
it already fixes `default`, Secret, ScreenCast, Screenshot and Inhibit, and
setting any of those again collides rather than overrides.

## Screenshot: mark-shot needs a mango detector *and* a config repoint

`modules/home/programs/apps/screenshot.nix` wraps the package in a `symlinkJoin`
that **adds** `mark-shot-window-detection-mango`. Upstream ships detectors for
gnome, hyprland, kde and niri and none for mango, so this one is added rather
than replacing a file of the same name.

The detector itself is short, and that is not an oversight: `mmsg get all-clients`
publishes each client's final **global logical** rectangle (`x`, `y`, `width`,
`height`), already accounting for tiled geometry and layer-shell reservations. So
it only filters `is_visible` / `is_minimized` and clips to mark-shot's capture
area. No scale arithmetic, no bar measurement. The niri equivalent needed 690
lines because niri published no rectangles for tiled windows; this one is 171.

`~/.config/mark-shot/config.json` records which detector to call, and mark-shot
rewrites that file itself, so Home Manager cannot own it. A machine that came
from the niri branch still says `mark-shot-window-detection-niri` there, which
under mango would silently run upstream's niri script and get nothing back. An
activation in `screenshot.nix` rewrites **only** `windowDetection.command` with
`jq`, leaving every other key alone.

`symlinkJoin` rather than `overrideAttrs` so editing the script does not
recompile the whole Qt application.

Theming for GTK/Qt applications (including which noctalia templates render what)
is the `desktop-apps` skill; this one owns the compositor and the IME.

## IPC

```sh
mmsg get all-clients      # {"clients":[…]}  x/y/width/height are logical
mmsg get all-monitors     # {"monitors":[…]} name/x/y/width/height/scale/active
mmsg get all-tags
mmsg get focusing-client
mmsg watch all-clients    # streaming variants of the same
```

`mmsg` ships in the same derivation as the compositor.

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
  and the compositor does not source it. Without the service the resource
  database is empty — `xrdb -query` prints nothing.

X clients get **physical** pixels, so each has to be told 96 × 1.5 = 144 itself.
`xwayland_ignore_scale` (default `0`) is what decides this and is easy to get
backwards: at `0`, `xwayland_preferred_scale()` returns the monitor scale and X
clients are asked to render at 1.5 — sharp. Setting it to `1` makes them render
at 1x and lets the compositor upscale — blurry. Leave it alone.
The 1.5x measurement was taken under niri + xwayland-satellite (QQ at 1251×1498 X
pixels against 834×999 logical, 2026-08-21). It carries over to mango's built-in
Xwayland **by source inspection, not re-measurement**: `src/manage/client.c`
converts with `X11 = logical * scale` and `xwayland_ignore_scale` defaults to 0.
Re-check with `xwininfo -root -tree` vs `mmsg get all-clients` the first time the
candidate window looks wrong.

**Which client is on XWayland has changed — do not trust older comments.**
`modules/home/programs/apps/im.nix` pins QQ to `--ozone-platform=wayland`
(nixpkgs' wrapper passed `--ozone-platform-hint=auto`, which was resolving to
X11); verified 2026-08-21, QQ now holds *zero* connections to
`@/tmp/.X11-unix/X0` and its input goes through text-input-v3. **`wechat-uos` is
the XWayland client now** — it pins `QT_QPA_PLATFORM=xcb`, and `Xft.dpi = 144` is
what keeps it readable.

Measure before and after with `xwininfo -root -tree | grep -i fcitx` (the window
is named `Fcitx5 Input Window`) and confirm the protocol with
`xlsclients` / `ss -xp`.

## Clipboard

The Wayland ↔ X11 bridge that `modules/home/services/clipboard.nix` used to
provide is **gone on this branch**. It existed only because xwayland-satellite
0.8.1/0.8.2 transferred 0 bytes in both directions; mango uses wlroots' built-in
Xwayland, which does selection sync inside the compositor, and running a manual
bridge alongside a working one risks a feedback loop. This has not been confirmed
on a running mango yet — if X11 copy/paste is dead, that module on `main` is the
thing to resurrect, not a new workaround.

`modules/home/services/cliphist.nix` is separate and unchanged: two
`wl-paste --watch cliphist store` user units (text and image) populate the
**cliphist history database**. Nothing here configures a viewer, so if history
looks empty, check `cliphist list` first — an empty list means one of those units
died (`systemctl --user status cliphist-watch-text`) and the problem is here,
while a populated list means the problem is in whatever is displaying it.

An app that must put *image data* rather than a file path on the clipboard has to
write both `wl-copy` and `xclip` itself — see `desktop-apps` on Thunar's
"Copy as Image".

## The greeter

`modules/system/desktop/greetd.nix` runs `noctalia-greeter` (its own flake input,
own nixpkgs pin, deliberately not `follows`-ed) as the greetd session, with the
same Bibata cursor as the desktop, and `session.default = "Mango"` — matching
`Name=Mango` in the session desktop file, not the package name.

`environment.pathsToLink = [ "/share/wayland-sessions" ]` carries no comment and
looks like noise. It is load-bearing: it is what puts session desktop files under
`/run/current-system/sw/share/wayland-sessions` where greetd can enumerate them.
`programs.mango.enable` registers the package in
`services.displayManager.sessionPackages`, but that alone does not link the files
into the system path. If you change it, test an actual logout, not just a
rebuild.
