# Greeter

Noctalia Greeter 1.7.0 provides the system login screen, defaulting to Mango with
Xorg available in a small session dropdown. Inputs are the host appearance and
display name/scale. `default.nix` is public; `greeter.nix`, `package.nix` and
`tech-greeter.patch` are private. `checks.nix` exposes `{ pkgs, nixos, appearance, ... }`.

R41 shares the lockscreen's Inter clock (72px), Chinese date (16px), 56px circular
account avatar and compact password row. `LC_TIME=zh_CN.UTF-8` is passed on the
existing greetd command. Inter uses installed Noto Sans CJK SC fallback for Chinese.
The greeter exposes one font field; no extra font configuration API is patched.
It lacks wallpaper blur/tint settings, so ImageMagick preprocesses the public
factory wallpaper 005 with blur/darkening. It cannot follow a private user's
mutable wallpaper before login; lockscreen still follows the current desktop.
No user wallpaper or account data is copied into the store.

Configuration alone retains a large login card and full-width session row. The
minimal surface patch clears that card, keeps the original avatar/authentication,
places the clock at the shared vertical anchor and narrows the native session
selector to 160px. The original panel draws only the 40px password row with an 8px radius;
the field is flat within it and the arrow uses a neutral ghost button. The
session dropdown uses neutral selection with blue text/border. Small screens
use separate clock and identity anchors below 700 logical pixels. It removes the former
tech frame, gradient/glow and machine telemetry. The existing greetd protocol,
PAM responses, session discovery, power controls and keyboard navigation remain
upstream. Source anchors fail the package build on patch drift; `greeter-tech`
checks the real executable, configured font/date and processed wallpaper.

The feature owns system greeter configuration, preprocessed public wallpaper and
font/cursor assets (Bibata-Modern-Ice from `bibata-cursors`, shared size 24). Removal withdraws those declarations, preserving accounts,
credentials and user/session state; select a replacement display manager first.
Isolated screenshots with a private fake greetd endpoint verify rendering, not
cold login, actual PAM authentication, display scaling or successful session start.
Those require integrator testing after deployment.
