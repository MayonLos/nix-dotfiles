{
  config,
  lib,
  pkgs,
  ...
}:

{
  programs.niri.settings = {
    xwayland-satellite = {
      enable = true;
      path = "${pkgs.xwayland-satellite}/bin/xwayland-satellite";
    };

    spawn-at-startup = [
      {
        command = [
            "dbus-update-activation-environment"
            "--systemd"
            "WAYLAND_DISPLAY"
            "XDG_CURRENT_DESKTOP"
            "XDG_SESSION_TYPE"
            "DISPLAY"
        ];
      }
      {
        command = [ "noctalia-shell" ];
      }
    ];
  };
}
