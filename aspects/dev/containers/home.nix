{
  lib,
  osConfig,
  pkgs,
  ...
}:
let
  docker = osConfig.systemd.user.services.docker;
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
          Environment = lib.mapAttrsToList (
            name: value: lib.escapeShellArg "${name}=${value}"
          ) docker.environment;
        };
        Install.WantedBy = [ "default.target" ];
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
