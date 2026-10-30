{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.mcsrv-mayon.tailscale;
  supportedBackend = builtins.elem config.networking.firewall.backend [
    "iptables"
    "nftables"
  ];
  nftBackend = config.networking.firewall.backend == "nftables";
  validPort = ''
    case "$1" in
      25565|25566|25567|25568|25569|25570|25571|25572|25573|25574|25575) ;;
      *) echo "mcsrv firewall only permits TCP ports 25565..25575" >&2; exit 2 ;;
    esac
  '';
  open =
    if nftBackend then
      pkgs.writeShellApplication {
        name = "mcsrv-firewall-open";
        runtimeInputs = [
          pkgs.nftables
          pkgs.util-linux
        ];
        text = ''
          ${validPort}
          exec 9>/run/mcsrv-firewall.lock
          flock -x 9
          if ! nft list set inet nixos-fw mcsrv-ports >/dev/null 2>&1; then
            nft add set inet nixos-fw mcsrv-ports \
              "{ type inet_service; flags timeout; timeout 90s; }" 2>/dev/null \
              || nft list set inet nixos-fw mcsrv-ports >/dev/null
          fi
          if ! nft -a list chain inet nixos-fw input-allow \
            | grep -Fq 'comment "mcsrv-mayon-lease"'; then
            nft add rule inet nixos-fw input-allow tcp dport @mcsrv-ports \
              accept comment "mcsrv-mayon-lease"
          fi
          nft add element inet nixos-fw mcsrv-ports "{ $1 timeout 90s }"
        '';
      }
    else
      pkgs.writeShellApplication {
        name = "mcsrv-firewall-open";
        runtimeInputs = [
          pkgs.iptables
          pkgs.util-linux
        ];
        text = ''
          ${validPort}
          exec 9>/run/mcsrv-firewall.lock
          flock -x 9
          for command in iptables ${lib.optionalString config.networking.enableIPv6 "ip6tables"}; do
            "$command" -w -C nixos-fw -p tcp --dport "$1" \
              -m comment --comment mcsrv-mayon-lease -j nixos-fw-accept 2>/dev/null \
              || "$command" -w -I nixos-fw 1 -p tcp --dport "$1" \
                -m comment --comment mcsrv-mayon-lease -j nixos-fw-accept
          done
        '';
      };
  close =
    if nftBackend then
      pkgs.writeShellApplication {
        name = "mcsrv-firewall-close";
        runtimeInputs = [
          pkgs.nftables
          pkgs.util-linux
        ];
        text = ''
          ${validPort}
          exec 9>/run/mcsrv-firewall.lock
          flock -x 9
          nft delete element inet nixos-fw mcsrv-ports "{ $1 }" 2>/dev/null || true
        '';
      }
    else
      pkgs.writeShellApplication {
        name = "mcsrv-firewall-close";
        runtimeInputs = [
          pkgs.iptables
          pkgs.util-linux
        ];
        text = ''
          ${validPort}
          exec 9>/run/mcsrv-firewall.lock
          flock -x 9
          for command in iptables ${lib.optionalString config.networking.enableIPv6 "ip6tables"}; do
            "$command" -w -D nixos-fw -p tcp --dport "$1" \
              -m comment --comment mcsrv-mayon-lease -j nixos-fw-accept 2>/dev/null || true
          done
        '';
      };
in
{
  options.services.mcsrv-mayon.tailscale = {
    enable = lib.mkEnableOption "optional Tailscale integration for Minecraft";
    operator = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Explicit local operator account allowed to manage the Tailscale daemon; no credentials are declared here.";
    };
  };
  config = {
    services.tailscale = lib.mkIf cfg.enable {
      enable = true;
      extraSetFlags = lib.optional (cfg.operator != null) "--operator=${cfg.operator}";
    };
    users.groups.mcsrv-firewall = { };
    security.polkit.enable = lib.mkDefault true;
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (action.id !== "org.freedesktop.systemd1.manage-units" ||
            !subject.isInGroup("mcsrv-firewall")) return;
        var unit = action.lookup("unit");
        var verb = action.lookup("verb");
        if (unit && /^mcsrv-firewall@2556[5-9]\.service$|^mcsrv-firewall@2557[0-5]\.service$/.test(unit) &&
            ["start", "stop", "restart"].indexOf(verb) >= 0) return polkit.Result.YES;
      });
    '';
    systemd.services."mcsrv-firewall@" = lib.mkIf supportedBackend {
      description = "Temporary game-server firewall lease on TCP port %i";
      serviceConfig = {
        Type = "simple";
        ExecStartPre = "${open}/bin/mcsrv-firewall-open %i";
        ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
        ExecStopPost = "${close}/bin/mcsrv-firewall-close %i";
        RuntimeMaxSec = "90s";
        TimeoutStopSec = "5s";
        Restart = "no";
        NoNewPrivileges = true;
        ProtectHome = true;
        PrivateTmp = true;
        CapabilityBoundingSet = [
          "CAP_NET_ADMIN"
          "CAP_NET_RAW"
        ];
      };
    };
  };
}
