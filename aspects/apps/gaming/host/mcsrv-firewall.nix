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
  lanId = ''
    if [[ ! "$1" =~ ^([1-9][0-9]*)_([1-9][0-9]*)_([1-9][0-9]*)_([1-9][0-9]*)$ ]]; then
      echo "invalid LAN lease identity" >&2; exit 2
    fi
    port="''${BASH_REMATCH[4]}"
    if (( ''${#port} > 5 || port < 1024 || port > 65535 )); then
      echo "invalid LAN port" >&2; exit 2
    fi
  '';
  # LAN and dedicated-server rules have separate identities so withdrawing one
  # kind of lease cannot accidentally withdraw the other's rule/set element.
  rule =
    lan: opening:
    let
      marker = if lan then "mcsrv-mayon-lan-lease" else "mcsrv-mayon-lease";
      set = if lan then "mcsrv-lan-ports" else "mcsrv-ports";
      name = "mcsrv-${if lan then "lan" else "firewall"}-${if opening then "open" else "close"}";
    in
    pkgs.writeShellApplication {
      inherit name;
      runtimeInputs = [
        pkgs.util-linux
        pkgs.coreutils
      ]
      ++ (if nftBackend then [ pkgs.nftables ] else [ pkgs.iptables ]);
      text = ''
        ${if lan then lanId else validPort}
        ${lib.optionalString (!lan) ''port="$1"''}
        exec 9>/run/mcsrv-firewall.lock
        flock -x 9
        ${lib.optionalString lan (
          if opening then
            ''
              install -d -m 0700 /run/mcsrv-lan-leases
              touch "/run/mcsrv-lan-leases/$1"
            ''
          else
            ''
              # Only a successfully authorized guard creates its own root-owned
              # marker. A rejected start's ExecStopPost cannot revoke another lease.
              test -f "/run/mcsrv-lan-leases/$1" || exit 0
              rm -- "/run/mcsrv-lan-leases/$1"
              shopt -s nullglob
              for other in /run/mcsrv-lan-leases/*_"$port"; do
                test ! -f "$other" || exit 0
              done
            ''
        )}
      ''
      + (
        if nftBackend then
          (
            if opening then
              ''
                if ! nft list set inet nixos-fw ${set} >/dev/null 2>&1; then
                  nft add set inet nixos-fw ${set} \
                    "{ type inet_service; flags timeout; timeout 90s; }" 2>/dev/null \
                    || nft list set inet nixos-fw ${set} >/dev/null
                fi
                if ! nft -a list chain inet nixos-fw input-allow \
                  | grep -Fq 'comment "${marker}"'; then
                  nft add rule inet nixos-fw input-allow tcp dport @${set} \
                    accept comment "${marker}"
                fi
                nft add element inet nixos-fw ${set} "{ $port timeout 90s }"
              ''
            else
              ''
                nft delete element inet nixos-fw ${set} "{ $port }" 2>/dev/null || true
              ''
          )
        else
          ''
            for command in iptables ${lib.optionalString config.networking.enableIPv6 "ip6tables"}; do
              ${
                if opening then
                  ''
                    "$command" -w -C nixos-fw -p tcp --dport "$port" \
                      -m comment --comment ${marker} -j nixos-fw-accept 2>/dev/null \
                      || "$command" -w -I nixos-fw 1 -p tcp --dport "$port" \
                        -m comment --comment ${marker} -j nixos-fw-accept
                  ''
                else
                  ''
                    "$command" -w -D nixos-fw -p tcp --dport "$port" \
                      -m comment --comment ${marker} -j nixos-fw-accept 2>/dev/null || true
                  ''
              }
            done
          ''
      );
    };
  open = rule false true;
  close = rule false false;
  lanOpen = rule true true;
  lanClose = rule true false;
  lanGuard = pkgs.writeShellApplication {
    name = "mcsrv-lan-guard";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      ${lanId}
      id="$1"
      # The caller cannot select the validator or proc root. Identity includes
      # starttime, preventing PID reuse; authorization is repeated every second.
      validate() { ${pkgs.mcsrvMayon}/bin/mcsrv-mayon lan-validate "$id" >/dev/null 2>&1; }
      validate || { echo "LAN listener validation failed" >&2; exit 1; }
      trap '${lanClose}/bin/mcsrv-lan-close "$id"' EXIT
      trap 'exit 0' TERM INT
      ${lanOpen}/bin/mcsrv-lan-open "$id"
      while sleep 1; do validate || exit 0; done
    '';
  };
  commonService = {
    Type = "simple";
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
        if (!unit || ["start", "stop", "restart"].indexOf(verb) < 0) return;
        if (/^mcsrv-firewall@2556[5-9]\.service$|^mcsrv-firewall@2557[0-5]\.service$/.test(unit)) return polkit.Result.YES;
        var lan = /^mcsrv-lan@([1-9][0-9]*)_[1-9][0-9]*_[1-9][0-9]*_[1-9][0-9]*\.service$/.exec(unit);
        if (lan) {
          // Subject exposes the user name, not a stable numeric uid property.
          // argv is passed directly to an immutable id binary, without a shell.
          var uid = polkit.spawn(["${pkgs.coreutils}/bin/id", "-u", subject.user]).trim();
          if (lan[1] === uid) return polkit.Result.YES;
        }
      });
    '';
    systemd.services."mcsrv-firewall@" = lib.mkIf supportedBackend {
      description = "Temporary game-server firewall lease on TCP port %i";
      serviceConfig = commonService // {
        ExecStartPre = "${open}/bin/mcsrv-firewall-open %i";
        ExecStart = "${pkgs.coreutils}/bin/sleep infinity";
        ExecStopPost = "${close}/bin/mcsrv-firewall-close %i";
      };
    };
    systemd.services."mcsrv-lan@" = lib.mkIf supportedBackend {
      description = "Validated Prism Minecraft LAN listener lease %i";
      serviceConfig = commonService // {
        ExecStart = "${lanGuard}/bin/mcsrv-lan-guard %i";
        ExecStopPost = "${lanClose}/bin/mcsrv-lan-close %i";
        # root must inspect another uid's proc fd/exe/cwd links. The validator
        # never opens game data or executes user-writable programs.
        CapabilityBoundingSet = commonService.CapabilityBoundingSet ++ [
          "CAP_SYS_PTRACE"
          "CAP_DAC_READ_SEARCH"
        ];
      };
    };
  };
}
