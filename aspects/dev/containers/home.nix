{
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  docker = osConfig.systemd.user.services.docker;
  dockerExecStart = docker.serviceConfig.ExecStart;
in
{
  # Reuse nixpkgs' generated rootless unit data. This keeps its pinned daemon
  # command, security limits, PATH, proxy environment, and restart behavior in
  # sync with the locked NixOS module while binding activation to this user.
  systemd.user = {
    services = {
      docker = {
        Unit = docker.unitConfig // {
          Description = docker.description;
        };
        Service = docker.serviceConfig // {
          ExecStart = "${dockerExecStart} --host=unix://%t/docker-private.sock";
          Environment = lib.mapAttrsToList (
            name: value: lib.escapeShellArg "${name}=${value}"
          ) docker.environment;
        };
        # The daemon is pulled in by docker-proxy.service after the first
        # client connects to docker.socket. It must not start at login.
        Install.WantedBy = [ ];
      };

      docker-proxy = {
        Unit = {
          Description = "Rootless Docker socket proxy";
          Requires = [ "docker.service" ];
          After = [ "docker.service" ];
        };
        Service = {
          ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd %t/docker-private.sock";
          Restart = "on-failure";
          RestartSec = "2s";
        };
      };

      docker-prune = {
        Unit.Description = "Prune old rootless Docker build cache";
        Service = {
          Type = "oneshot";
          # Automatic maintenance only removes build cache. Stopped containers
          # may hold unfinished experiments in their writable layer.
          ExecStart = "${pkgs.docker}/bin/docker --host unix://%t/docker.sock builder prune -f --filter until=168h";
        };
      };

    };

    sockets.docker = {
      Unit.Description = "On-demand rootless Docker API socket";
      Socket = {
        ListenStream = "%t/docker.sock";
        Service = "docker-proxy.service";
        SocketMode = "0600";
        RemoveOnStop = true;
      };
      Install.WantedBy = [ "sockets.target" ];
    };

    timers.docker-prune = {
      Unit.Description = "Weekly rootless Docker build cache cleanup";
      Timer = {
        OnCalendar = "weekly";
        Persistent = true;
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };

}
