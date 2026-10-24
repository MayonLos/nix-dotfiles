{ pkgs, ... }:
{
  users.groups.legion-conservation = { };
  # sysfs attributes do not inherit udev GROUP/MODE for device nodes.
  # Bind/change also covers a driver rebind; no privileged runtime helper.
  services.udev.extraRules = ''
    ACTION=="add|bind|change", SUBSYSTEM=="platform", DRIVER=="ideapad_acpi", TEST=="conservation_mode", RUN+="${pkgs.coreutils}/bin/chgrp legion-conservation /sys%p/conservation_mode", RUN+="${pkgs.coreutils}/bin/chmod g+w /sys%p/conservation_mode"
  '';
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
