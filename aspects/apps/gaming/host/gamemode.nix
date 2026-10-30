{ pkgs, ... }:
let
  tools = import ../tools.nix { inherit pkgs; };
  inhibitorReady = pkgs.writeShellScript "gaming-inhibitor-ready" ''
    # systemd's safe_fork clears NOTIFY_SOCKET in systemd-inhibit's child.
    # The manager expands it into an argument before that fork occurs.
    NOTIFY_SOCKET="$1" ${pkgs.systemd}/bin/systemd-notify --ready
    exec ${pkgs.coreutils}/bin/sleep infinity
  '';
in
{
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id === "org.freedesktop.UPower.PowerProfiles.switch-profile" &&
          subject.isInGroup("gamemode")) {
        return polkit.Result.YES;
      }
    });
  '';
  programs.gamemode = {
    enable = true;
    settings = {
      general = {
        # PPD owns the governor; the package adds an explicit opt-out to 1.8.2.
        desiredgov = "ignore";
        igpu_power_threshold = 10000;
        disable_splitlock = 0;
        ioprio = "off";
        # The logind inhibitor below replaces GameMode's desktop-specific one.
        inhibit_screensaver = 0;
      };
      # NV-CONTROL clock attributes aren't supported by this Wayland laptop.
      gpu.apply_gpu_optimisations = "";
      custom = {
        # Allow inner command timeouts plus rollback to finish before GameMode
        # terminates a hook. Each subprocess is bounded by fifteen seconds.
        script_timeout = 150;
        start = "${tools.gaming-mode-hook}/bin/gaming-mode-hook start";
        end = "${tools.gaming-mode-hook}/bin/gaming-mode-hook end";
      };
      # Match executable path fragments, NOT "steam" (which matches steamapps).
      # Per-game gamemoderun reaches games; launchers/helpers must not hold a
      # performance profile for the entire time the Steam UI is open.
      filter.blacklist = [
        "/ubuntu12_32/steam"
        "/ubuntu12_64/steam"
        "/steamwebhelper"
        "/steam-runtime-"
        "/steam-runtime/"
        "/pressure-vessel/"
        "/reaper"
        "/bash"
        "/dash"
        "/bin/sh"
        "/bin/env"
      ];
    };
  };
  # No login wants. GameMode hooks acquire only this game's idle inhibitor;
  # Noctalia observes logind BlockInhibited and suppresses its idle actions.
  systemd.user.services.gaming-idle-inhibit = {
    description = "GameMode idle inhibitor";
    partOf = [ "gamemoded.service" ];
    serviceConfig = {
      Type = "notify";
      NotifyAccess = "all";
      TimeoutStartSec = 10;
      TimeoutStopSec = 5;
      ExecStart = "${pkgs.systemd}/bin/systemd-inhibit --no-ask-password --what=idle --mode=block --who=GameMode --why=Gaming ${inhibitorReady} \${NOTIFY_SOCKET}";
      Restart = "on-failure";
    };
  };
  systemd.user.services.gamemoded.serviceConfig.ExecStopPost =
    "${tools.gaming-mode-hook}/bin/gaming-mode-hook end";
  environment.systemPackages = builtins.attrValues tools;
}
