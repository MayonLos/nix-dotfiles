{ config, pkgs, ... }:
{
  # Minimal Wayland-native login on tty1: greetd + tuigreet (TUI greeter, needs
  # no compositor of its own) launches niri-session directly.
  services.greetd = {
    enable = true;
    settings.default_session = {
      # --time shows a clock, --remember keeps the last username,
      # --remember-session keeps the last chosen session, --cmd is the default.
      command =
        "${pkgs.tuigreet}/bin/tuigreet --time --remember --remember-session "
        + "--cmd ${config.programs.niri.package}/bin/niri-session";
      user = "greeter";
    };
  };

  # Without this, NixOS injects a stripped PATH via Environment= on niri.service
  # which shadows the user-manager PATH and makes niri black-screen when started
  # from greetd (nixpkgs #430230). Launching from a TTY by hand is unaffected.
  systemd.user.services.niri.enableDefaultPath = false;
}
