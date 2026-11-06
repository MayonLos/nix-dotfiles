{
  pkgs,
  lib,
  tunnel,
}:
let
  # The token is read from the runtime secret by frpc itself (tokenSource), so
  # this store file holds only public settings.
  config = (pkgs.formats.toml { }).generate "frpc.toml" {
    serverAddr = tunnel.server;
    inherit (tunnel) serverPort;
    # Keep retrying while the relay or the network is down instead of exiting.
    loginFailExit = false;
    auth = {
      method = "token";
      tokenSource = {
        type = "file";
        file.path = tunnel.tokenFile;
      };
    };
    transport.tls.enable = true;
    log = {
      to = "console";
      level = "info";
    };
    proxies = lib.mapAttrsToList (name: proxy: {
      inherit name;
      type = proxy.protocol;
      localIP = "127.0.0.1";
      inherit (proxy) localPort remotePort;
    }) tunnel.proxies;
  };

  addresses = lib.concatStringsSep ", " (
    lib.mapAttrsToList (
      name: proxy: "${name} ${tunnel.server}:${toString proxy.remotePort}"
    ) tunnel.proxies
  );

  command = pkgs.writeShellApplication {
    name = "game-tunnel";
    runtimeInputs = [ pkgs.systemd ];
    text = ''
      case "''${1:-status}" in
        start)
          systemctl --user start game-tunnel.service
          echo "Tunnel started: ${addresses}"
          ;;
        stop) systemctl --user stop game-tunnel.service ;;
        status)
          systemctl --user --no-pager status game-tunnel.service || true
          ;;
        log) journalctl --user -u game-tunnel.service -n 30 --no-pager ;;
        *)
          echo "usage: game-tunnel [start|stop|status|log]" >&2
          exit 2
          ;;
      esac
    '';
  };
in
{
  home.packages = [ command ];

  # Started by hand while hosting; no login wants, no timer.
  systemd.user.services.game-tunnel = {
    Unit = {
      Description = "frp client publishing local game servers through ${tunnel.server}";
      After = [ "network-online.target" ];
    };
    Service = {
      ExecStart = "${pkgs.frp}/bin/frpc -c ${config}";
      Restart = "on-failure";
      RestartSec = 10;
    };
  };
}
