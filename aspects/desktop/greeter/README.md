# Greeter

greetd login screen with two selectable backends (`nixDotfiles.greeterBackend`):

- **`noctalia`** (this branch's default): Noctalia Greeter 1.7.1. greetd starts
  `noctalia-greeter-session`, which brings its own wlroots compositor and
  renders the login UI. Sessions are discovered from the installed
  `share/wayland-sessions` entries (Mango, Umbriel), so the old
  `/etc/greetd/environments` list is not used. The generated
  `/var/lib/noctalia-greeter/greeter.toml` pins the One Dark palette, factory
  wallpaper, `eDP-1` output at 1.5 scale, US keyboard, cursor theme and Mango as
  the default session. `greeter-tech` checks the greetd command, the generated
  TOML and the greetd user.
- **`gtkgreet`** (previous behaviour): a private sway compositor runs gtkgreet
  with a One Dark stylesheet and the 128-byte-safe `mango-login` script. This
  path remains for rollback and is unchanged; see the git history for the
  detailed notes on gtkgreet's clock/background/scale limitations.

Both backends keep `services.greetd.greeterManagesPlymouth = false`. `default.nix`
is public; `greeter.nix` (gtkgreet), `noctalia.nix` (Noctalia Greeter) and
`checks.nix` are private.

Removing the feature withdraws the greetd session, stylesheet/TOML and login
scripts. Accounts, credentials and user sessions stay; select another display
manager before removing it if the machine should still boot to a login screen.
