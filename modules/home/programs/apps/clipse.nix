{ pkgs, ... }:
{
  home.packages = [ pkgs.clipse ];

  systemd.user.services.clipse = {
    Unit = {
      Description = "clipse clipboard listener";
      PartOf = [ "graphical-session.target" ];
      After = [ "graphical-session.target" ];
    };
    Service = {
      Type = "simple";
      ExecStart = "${pkgs.clipse}/bin/clipse -listen";
      Restart = "on-failure";
      RestartSec = 1;
    };
    Install = {
      WantedBy = [ "graphical-session.target" ];
    };
  };
}
