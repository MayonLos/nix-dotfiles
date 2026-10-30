{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.mayon-clash;
  account = config.users.users.${cfg.user};
  data = "${account.home}/.local/share/mayon-clash";
  geoip = "${pkgs.v2ray-geoip}/share/v2ray/geoip.dat";
  geosite = "${pkgs.v2ray-domain-list-community}/share/v2ray/geosite.dat";
in
{
  options.services.mayon-clash.user = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = "The bound local account owning the manual native Clash trial.";
  };
  config = lib.mkIf (cfg.user != null) {
    assertions = [
      {
        assertion = config.users.users ? ${cfg.user};
        message = "mayon-clash needs a declared bound user";
      }
    ];
    networking.firewall.trustedInterfaces = [ "mayon-clash" ];
    security.polkit.enable = true;
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id === "org.freedesktop.systemd1.manage-units" &&
            subject.user === ${builtins.toJSON cfg.user} &&
            action.lookup("unit") === "mayon-clash.service" &&
            ["start", "stop", "restart"].indexOf(action.lookup("verb")) !== -1) {
          return polkit.Result.YES;
        }
      });
    '';
    # The TUI creates the private data directory before producing a config.
    # There is deliberately no wantedBy, timer, socket activation or restart policy.
    systemd.services.mayon-clash = {
      description = "Manual Mayon Clash (Mihomo native trial)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      serviceConfig = {
        User = cfg.user;
        Group = account.group;
        ExecStartPre = "${pkgs.mayonTui.clash}/bin/mayon-clash-preflight ${lib.escapeShellArg data} ${lib.getExe pkgs.mihomo} ${geoip} ${geosite} ${pkgs.dbip-country-lite.mmdb}";
        ExecStart = "${lib.getExe pkgs.mihomo} -d ${lib.escapeShellArg data} -f ${lib.escapeShellArg "${data}/config.yaml"}";
        # 1.19.24 registers SIGTERM after TUN setup; close TUN through its mutex
        # before systemd signals a core that may still be initializing.
        ExecStop = "${pkgs.mayonTui.clash}/bin/mayon-clash-preflight stop /run/mayon-clash/mihomo.sock ${lib.escapeShellArg data} $MAINPID";
        RuntimeDirectory = "mayon-clash";
        RuntimeDirectoryMode = "0700";
        UMask = "0077";
        TimeoutStartSec = 60;
        TimeoutStopSec = 30;
        AmbientCapabilities = [
          "CAP_NET_ADMIN"
          "CAP_NET_BIND_SERVICE"
        ];
        CapabilityBoundingSet = [
          "CAP_NET_ADMIN"
          "CAP_NET_BIND_SERVICE"
        ];
        NoNewPrivileges = true;
        # Locked upstream tunMode relaxations; AF_UNIX additionally needed for our controller.
        PrivateDevices = false;
        PrivateUsers = false;
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_NETLINK"
          "AF_UNIX"
        ];
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        PrivateMounts = true;
        PrivateTmp = true;
        ProcSubset = "pid";
        ProtectClock = true;
        ProtectControlGroups = true;
        ProtectHome = "read-only";
        # Missing data must reach the fixed Chinese preflight diagnostic.
        ReadWritePaths = [ "-${data}" ];
        ProtectHostname = true;
        ProtectKernelLogs = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectProc = "invisible";
        ProtectSystem = "strict";
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RestrictNamespaces = true;
        SystemCallArchitectures = "native";
        SystemCallFilter = [
          "@system-service"
          "bpf"
        ];
        # Core logs remain available through the private API. Prevent subscription
        # or provider diagnostics from persisting URL credentials in the journal.
        StandardOutput = "null";
        StandardError = "journal";
      };
    };
  };
}
