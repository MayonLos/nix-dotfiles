{ pkgs, ... }:
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

      { command = [ "${pkgs.swww}/bin/swww-daemon" ]; }

      {
        command = [
          "sh"
          "-c"
          "sleep 0.3 && ${pkgs.swww}/bin/swww-daemon -n overview"
        ];
      }

      {
        command = [
          "sh"
          "-c"
          "sleep 0.8 && ${pkgs.swww}/bin/swww img ${../wallpaper/wallpaper.jpg}"
        ];
      }

      {
        command = [
          "sh"
          "-c"
          "sleep 0.8 && ${pkgs.swww}/bin/swww img ${../wallpaper/overview.jpg} -n overview"
        ];
      }

      { command = [ "waybar" ]; }
    ];
  };
}
