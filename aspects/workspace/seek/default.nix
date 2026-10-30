_: {
  den.aspects.seek.homeManager =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.seek ];
      # CLI and both desktop sessions share this user timer. There is no daemon
      # and no session target dependency; selecting the feature owns this unit.
      systemd.user.services.seek-index = {
        Unit = {
          Description = "Incremental private seek index (confirmed scope only)";
          ConditionPathExists = "%h/.config/seek/config.toml";
        };
        Service = {
          Type = "oneshot";
          ExecStart = "${pkgs.seek}/bin/seek index --background";
          Nice = 19;
          IOSchedulingClass = "idle";
          CPUQuota = "50%";
          MemoryHigh = "768M";
          MemoryMax = "2G";
          UMask = "0077";
          NoNewPrivileges = true;
          PrivateTmp = true;
          TimeoutStartSec = "2h";
        };
      };
      systemd.user.timers.seek-index = {
        Unit.Description = "Periodically update the confirmed seek index";
        Timer = {
          OnBootSec = "15m";
          OnUnitInactiveSec = "2h";
          RandomizedDelaySec = "10m";
          Persistent = true;
        };
        Install.WantedBy = [ "timers.target" ];
      };
      xdg.desktopEntries.seek = {
        name = "Seek 本地资料";
        comment = "Search local notes and documents privately";
        exec = "${pkgs.kitty}/bin/kitty --class seek --title Seek ${pkgs.seek}/bin/seek tui";
        icon = "system-search";
        terminal = false;
        categories = [
          "Utility"
          "Education"
        ];
      };
    };
}
