{ pkgs, ... }:
{
  virtualisation.docker.rootless = {
    enable = true;
    setSocketVariable = true;
  };

  systemd.user = {
    services.docker-prune = {
      description = "Prune unused rootless Docker data";
      unitConfig.ConditionUser = "mayon";
      path = [ pkgs.docker ];
      script = ''docker --host "unix://$XDG_RUNTIME_DIR/docker.sock" system prune -f'';
      serviceConfig.Type = "oneshot";
    };
    timers.docker-prune = {
      wantedBy = [ "timers.target" ];
      unitConfig.ConditionUser = "mayon";
      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
      };
    };
  };
}
