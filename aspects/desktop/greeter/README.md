# Greeter

gtkgreet 0.8 is the login screen. `default.nix` is public. `greeter.nix` is private.
`checks.nix` exposes `{ pkgs, lib, nixos, appearance, ... }`.

cage 0.3.0 has no per-output scale. The greeter compositor is therefore sway, and
`output <display.name> scale <display.scale>` comes from host facts. On this host
that is `eDP-1` at `1.5`. Other outputs keep sway's default scale of 1. sway exits
when gtkgreet exits. `services.greetd.greeterManagesPlymouth` stays false, so greetd
still waits for Plymouth.

gtkgreet's `-b` draws a background 1:1 and is wrong once the scale is not 1. The
stylesheet sets `background-size: cover` on the public factory wallpaper after the
existing ImageMagick blur/darken. The greeter cannot follow a user's mutable
wallpaper before login. No user wallpaper or account data is copied into the store.

gtkgreet 0.8 copies the selected command into a 128-byte buffer and passes that
whole string as greetd's only argv element. The login command is the short
`mango-login` script: it exports `XDG_SESSION_TYPE=wayland`,
`XDG_CURRENT_DESKTOP=mango:wlroots` and `XDG_SESSION_DESKTOP=mango`, then execs
`programs.mango.package`. The same path is the only `/etc/greetd/environments`
line and gtkgreet's `-c` default. A command line with arguments would not run.

gtkgreet draws its own clock as `%02d:%02d` at Pango size 32000 (31.25 pt) on the
focused output. It does not draw the lockscreen's 72 px clock, Chinese date or
circular avatar; those stay on the Noctalia lock screen. It also has no power
buttons. The stylesheet only sets the One Dark wallpaper, card, field and cursor
colors. Inter and Noto Sans CJK SC are system fonts. Bibata-Modern-Ice size 24 is
passed with `XCURSOR_THEME`, `XCURSOR_SIZE` and `XCURSOR_PATH` because greetd
starts from an empty environment.

`greeter-tech` checks the gtkgreet and sway executables, the 127-byte login
script, the desktop names, the scale line, the cover wallpaper and the cursor
file. It does not start PAM, sway or a cold login. Those still need a reboot on
the target machine. Removing the feature withdraws the greetd session, stylesheet
and login script. Accounts, credentials and user sessions stay. Select another
display manager before removing it if the machine should still boot to a login
screen.
