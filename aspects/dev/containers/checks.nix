{ pkgs, home, ... }:
let
  docker = home.systemd.user.services.docker;
  proxy = home.systemd.user.services.docker-proxy;
  prune = home.systemd.user.services.docker-prune;
  socket = home.systemd.user.sockets.docker;
  pruneTimer = home.systemd.user.timers.docker-prune;
in
assert docker.Install.WantedBy == [ ];
assert
  builtins.match ".*docker-private\\.sock.*" (pkgs.lib.concatStringsSep "\n" docker.Service.ExecStart)
  != null;
assert docker.Service.Restart == "always";
assert socket.Socket.ListenStream == "%t/docker.sock";
assert socket.Socket.Service == "docker-proxy.service";
assert socket.Socket.SocketMode == "0600";
assert socket.Install.WantedBy == [ "sockets.target" ];
assert proxy.Unit.Requires == [ "docker.service" ];
assert proxy.Unit.After == [ "docker.service" ];
assert
  builtins.match ".*systemd-socket-proxyd.*docker-private\\.sock.*" (
    pkgs.lib.concatStringsSep "\n" proxy.Service.ExecStart
  ) != null;
assert
  builtins.match ".*unix://%t/docker.sock.*builder prune.*until=168h.*" (
    pkgs.lib.concatStringsSep "\n" prune.Service.ExecStart
  ) != null;
assert pruneTimer.Timer.Persistent;
assert !(proxy.Service ? StopWhenUnneeded);
{
  rootless-docker-socket-proxy =
    pkgs.runCommand "rootless-docker-socket-proxy-check"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.systemd
        ];
        SYSTEMD_SOCKET_ACTIVATE = "${pkgs.systemd}/bin/systemd-socket-activate";
        SYSTEMD_SOCKET_PROXYD = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd";
      }
      ''
        python3 ${./resources/test_socket_activation.py}
        touch "$out"
      '';
}
