{ pkgs, ... }:
let
  mkGraphicalService = import ../../../lib/graphical-service.nix;

  mkWatch =
    type: description:
    mkGraphicalService {
      inherit description;
      service = {
        Type = "simple";
        ExecStart = "${pkgs.wl-clipboard}/bin/wl-paste --type ${type} --watch ${pkgs.cliphist}/bin/cliphist store";
        Restart = "on-failure";
        RestartSec = 2;
      };
    };
in
{
  systemd.user.services.cliphist-watch-text = mkWatch "text" "cliphist text clipboard watcher";
  systemd.user.services.cliphist-watch-image = mkWatch "image" "cliphist image clipboard watcher";
}
