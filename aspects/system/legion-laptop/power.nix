_: {
  services = {
    thermald.enable = true;
    power-profiles-daemon.enable = true;
    upower.enable = true;
    scx = {
      enable = true;
      scheduler = "scx_lavd";
      # In 1.1.2, no arguments selects load-based autopilot, not fixed balanced.
      # --autopower follows power profiles and has caused compositor wakeup
      # delays in power-saver elsewhere; retain the default instead.
      extraArgs = [ ];
    };
  };
}
