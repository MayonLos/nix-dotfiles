# Mango session

Selectable Mango Wayland desktop for this host. It bundles the Mango
configuration, its scratchpads/window rules, screenshots and OCR, and the
host-side Mango/portal modules. It does **not** own a desktop shell any more:
the bar, launcher, notifications, OSD, lock screen, wallpaper and clipboard
history are the shared Noctalia shell from `desktop/noctalia-shell`, started by
`noctalia.service` from `mango-session.target`. It does not select the login
greeter; greeter is a separate feature.

## Inputs and outputs

Inputs are `user.appearance` (palette, fonts, cursor, icon theme,
`reducedMotion`), host display/GPU facts, and the public
`nixDotfiles.graphicalSessionTargets` option from `desktop/session-support`.

Outputs are:

- `~/.config/mango/config.conf`, the keybind help and the append-only
  `keys-mayon/bindings.json` export;
- the shared Noctalia configuration/palette, `noctalia.service`,
  `polkit-gnome-authentication-agent-1.service` and `clipboard-bridge.service`
  (state and runtime data stay under `~/.local/state/noctalia` and
  `~/.cache/noctalia`);
- the `desktop-benchmark` user service from `desktop/noctalia-benchmark`;
- screenshot/scroll capture via `mark-shot`, whole-screen capture and region
  capture through Noctalia IPC, OCR wrappers (`ocr-region`, `ocr-screen`);
- host-side `programs.mango` (patched package) and portal routing.

`default.nix` is the public aspect entry. `mango.nix`, `mango/`,
`screenshot.nix`, `tesseract-ocr.nix`, `session-environment.nix` and `host/`
are private implementation. `checks.nix` is the explicit public test hook
(`mango-blur-sampling` and the unified-Noctalia session contract).

## Removed in the unified shell experiment

mangobar, mako, fuzzel, swayosd, swaylock/swayidle, swaybg/sweetbgd/Matuwall,
cliphist/cliphist-tui/wl-clip-persist and the custom clipboard history/paste
helper are no longer installed by this feature. The X11↔Wayland clipboard
bridge moved into `desktop/noctalia-shell/services.nix` because all three
sessions use XWayland. `pam.services.swaylock` and the SwayOSD libinput backend
were dropped with them; Noctalia locks through the login PAM stack and draws
its own OSD.

## Style

The compositor keeps the repository's square, low-contrast look: 1px border in
One Dark blue/border, no compositor blur beyond the Mango blur level, and the
leftover window rules only for real app quirks (virt-manager, dialogs,
scratchpads, mark-shot overlays). The top bar is Noctalia's 30px fully
transparent bar with workspaces/window title/CPU/MEM/clock from the shared
configuration.

## Removing this feature

Drop the `interactive-session` bundle/include and the host's Mango/portal
imports: the compositor package, its config and the shared Noctalia services
disappear. User state under `~/.config/mango`, Noctalia state/cache and the
`Pictures/Wallpapers` link farm were already user data and are not removed.
