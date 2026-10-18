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
  systemd.user.services.docker = {
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

  systemd.user.services.docker-prune = {
    Unit.Description = "Prune unused rootless Docker data";
    Service = {
      Type = "oneshot";
      ExecStart = "${pkgs.docker}/bin/docker --host unix://%t/docker.sock system prune -f";
    };
  };

  systemd.user.timers.docker-prune = {
    Unit.Description = "Weekly rootless Docker prune";
    Timer = {
      OnCalendar = "weekly";
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
