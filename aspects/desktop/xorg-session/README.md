# Xorg dwm session

Provides the optional real Xorg session for applications that require native X11 capture. It is selected separately from the default Mango session; the sessions are alternatives. Inputs are the user palette and host display facts such as X11 DPI.

Outputs include a parameterized dwm package, dmenu, Picom, UI/lock configuration, a supervisor and exit command, clipboard and notification services, and the `xorg-session.target` lifecycle. Host-side Xorg support is routed through `xorg-session-host`. The public package factory is `dwm/package.nix`, which accepts `pkgs`, `palette`, and profile/DPI parameters; other Nix files are private.

`checks.nix` is a public test hook with signature `{ pkgs, lib, system, nixos, home, appearance }` (as needed). It exercises session scripts and command behavior but does not log into Xorg or prove capture in QQ. Removing this feature withdraws Xorg session declarations after activation; it retains user configuration and application state. It does not change the Mango default or apply a system switch.
