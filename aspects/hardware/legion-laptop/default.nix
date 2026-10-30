_: {
  den.schema.host.imports = [ ./contract.nix ];
  den.aspects = {
    legion-laptop = { host, ... }: {
      nixos.imports = [
        ./boot.nix
        ./firmware.nix
        ./intel-video.nix
        ./nvidia.nix
        (import ./bluetooth.nix host.facts.bluetooth)
        ./power.nix
        ./memory.nix
      ];
    };
    legion-laptop-user = { host, ... }: {
      user.extraGroups = [
        "legion-conservation"
        "power-mayon"
      ];
      homeManager = { config, pkgs, ... }: {
        # Only the selected user's timer requests this unit. It does no sensor
        # polling and has no side effects until the mutable opt-in is enabled.
        systemd.user.services.power-mayon-auto = {
          Unit = {
            Description = "Opt-in power-mayon AC/battery profile rules";
            ConditionPathExists = "${config.xdg.configHome}/power-mayon/config.json";
          };
          Service = {
            Type = "oneshot";
            Environment = [
              "XDG_CONFIG_HOME=${config.xdg.configHome}"
              "XDG_STATE_HOME=${config.xdg.stateHome}"
            ];
            ExecStart = "${pkgs.powerMayon}/bin/power-mayon auto tick";
            UMask = "0077";
            NoNewPrivileges = true;
            TimeoutStartSec = 20;
          };
        };
        systemd.user.timers.power-mayon-auto = {
          Unit.Description = "Check opt-in power-mayon rules every 30 seconds";
          Timer = {
            OnCalendar = "*-*-* *:*:00,30";
            AccuracySec = "1s";
          };
          Install.WantedBy = [ "timers.target" ];
        };
        programs.mpv.config.hwdec = host.facts.gpu.mpvHwdec;
        home.packages = [
          pkgs.powerMayon
          pkgs.lenovo-legion
          (import ./conservation.nix { inherit pkgs; })
        ];
      };
    };
  };
}
