{ palette }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  mkGraphicalService = import ../../../lib/service.nix;
  wallpapers = import ../../appearance/appearance/resources/wallpaper/package.nix {
    inherit pkgs palette;
  };
  wallpaperRoot = "${config.home.homeDirectory}/Pictures/Wallpapers";
in
{
  # The managed wallpaper set ships in the store as a directory of links. HM
  # owns only this one link; user pictures stay outside the store and Git.
  home = {
    file."Pictures/Wallpapers/managed".source = wallpapers.directory;

    activation.wallpaperLocalDirectory = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      local_wallpapers=${lib.escapeShellArg "${wallpaperRoot}/local"}
      if [ -e "$local_wallpapers" ] || [ -L "$local_wallpapers" ]; then
        if [ ! -d "$local_wallpapers" ]; then
          echo "Wallpapers/local exists and is not a directory; preserving it" >&2
          exit 1
        fi
      else
        run mkdir -p -- "$local_wallpapers"
      fi
    '';
  };

  # Mango itself paints only `root_color`; it has no wallpaper renderer. One
  # static swaybg process draws the selected wallpaper in its own layer behind
  # every window. The chosen file is a Nix argument (the appearance wallpaper
  # factory's default), so changing it is a rebuild, not a runtime setting.
  systemd.user.services.swaybg = mkGraphicalService {
    target = "mango-session.target";
    description = "static Wayland wallpaper renderer";
    unit = {
      StartLimitIntervalSec = 60;
      StartLimitBurst = 3;
    };
    service = {
      ExecCondition = "${pkgs.runtimeShell} -c '[ -n \"$WAYLAND_DISPLAY\" ]'";
      ExecStart = "${lib.getExe pkgs.swaybg} -i ${wallpapers.default} -m fill -c ${lib.removePrefix "#" palette.bg}";
      Restart = "always";
      RestartSec = 2;
    };
  };
}
