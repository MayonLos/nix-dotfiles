{ palette }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # One entry point for keybind, idle timeout and sleep hook. Pausing media
  # mirrors the removed shell's session-locked hook; a missing player must not
  # prevent locking.
  lock = pkgs.writeShellScriptBin "session-lock" ''
    ${lib.getExe pkgs.playerctl} pause >/dev/null 2>&1 || true
    exec ${lib.getExe config.programs.swaylock.package} -f
  '';
  lockCommand = lib.getExe lock;
in
{
  # Mango announces ext-session-lock-v1 (the pinned binary exposes
  # handle_new_session_lock/unlock), so a standalone swaylock client owns the
  # lock surface without a second daemon. PAM is configured host-side in
  # mango-session/host/mango.nix; without a PAM service swaylock cannot unlock.
  home.packages = [ lock ];

  programs.swaylock = {
    enable = true;
    settings = {
      color = "${lib.removePrefix "#" palette.bg}ff";
      inside-color = "${lib.removePrefix "#" palette.bg}e6";
      inside-clear-color = "${lib.removePrefix "#" palette.bg}e6";
      inside-ver-color = "${lib.removePrefix "#" palette.bg}e6";
      inside-wrong-color = "${lib.removePrefix "#" palette.red}e6";
      key-hl-color = "${lib.removePrefix "#" palette.blue}ff";
      bs-hl-color = "${lib.removePrefix "#" palette.red}ff";
      line-color = "${lib.removePrefix "#" palette.bg}00";
      line-clear-color = "${lib.removePrefix "#" palette.bg}00";
      line-ver-color = "${lib.removePrefix "#" palette.blue}ff";
      line-wrong-color = "${lib.removePrefix "#" palette.red}ff";
      text-color = "${lib.removePrefix "#" palette.brightFg}ff";
      text-clear-color = "${lib.removePrefix "#" palette.brightFg}ff";
      text-ver-color = "${lib.removePrefix "#" palette.brightFg}ff";
      text-wrong-color = "${lib.removePrefix "#" palette.brightFg}ff";
      ring-color = "${lib.removePrefix "#" palette.surface}ff";
      ring-clear-color = "${lib.removePrefix "#" palette.surface}ff";
      ring-ver-color = "${lib.removePrefix "#" palette.surface}ff";
      ring-wrong-color = "${lib.removePrefix "#" palette.surface}ff";
      separator-color = "${lib.removePrefix "#" palette.border}ff";
      font = palette.fonts.sans;
      font-size = 16;
      indicator-radius = 120;
      indicator-thickness = 6;
      show-failed-attempts = true;
      fade-in = 0.15;
      effect-blur = "8x4";
      effect-vignette = "0.5:0.5";
    };
  };

  # swayidle owns the idle actions. Lock at 15 minutes and suspend
  # (locking first) after an hour; a logind sleep request from any source also
  # locks before the system suspends. Screen-off is intentionally not emulated
  # here: Mango has no IPC action for output power in the pinned version.
  services.swayidle = {
    enable = true;
    systemdTargets = [ "mango-session.target" ];
    timeouts = [
      {
        timeout = 900;
        command = lockCommand;
      }
      {
        timeout = 3600;
        command = "${lockCommand}; ${pkgs.systemd}/bin/systemctl suspend";
      }
    ];
    events = {
      before-sleep = lockCommand;
    };
  };

  systemd.user.services.swayidle = {
    Unit = {
      StartLimitIntervalSec = 60;
      StartLimitBurst = 3;
    };
    Service = {
      Restart = "always";
      RestartSec = 2;
      UnsetEnvironment = [ "LC_ALL" ];
    };
  };
}
