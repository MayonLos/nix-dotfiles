_: {
  den.aspects.voice-input.homeManager = { pkgs, config, ... }: {
    home.packages = [ pkgs.mayonVoice ];
    i18n.inputMethod.fcitx5.addons = [ pkgs.mayonVoice.fcitxAddon ];
    systemd.user.sockets.mayon-voice = {
      Unit = {
        Description = "Local voice input control socket";
        PartOf = config.nixDotfiles.graphicalSessionTargets;
        After = config.nixDotfiles.graphicalSessionTargets;
      };
      Socket = {
        ListenStream = "%t/mayon-voice/control.sock";
        SocketMode = "0600";
        DirectoryMode = "0700";
        RemoveOnStop = true;
      };
      Install.WantedBy = config.nixDotfiles.graphicalSessionTargets;
    };
    systemd.user.services.mayon-voice = {
      Unit = {
        Description = "Local offline Chinese voice input";
        PartOf = config.nixDotfiles.graphicalSessionTargets;
        After = config.nixDotfiles.graphicalSessionTargets;
      };
      Service = {
        ExecStart = "${pkgs.mayonVoice}/bin/mayon-voice daemon";
        UMask = "0077";
        Restart = "on-failure";
        RestartSec = 2;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ReadWritePaths = [ "%t/mayon-voice" ];
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
        # Audio, models and secrets are accessed as the selected user; no new devices/privileges.
        KillMode = "control-group";
        TimeoutStopSec = 3;
      };
    };
  };
}
