{ pkgs, ... }:
let
  tools = import ../tools.nix { inherit pkgs; };
  inhibitorReady = pkgs.writeShellScript "gaming-inhibitor-ready" ''
    ${pkgs.systemd}/bin/systemd-notify --ready
    exec ${pkgs.coreutils}/bin/sleep infinity
  '';
in
{
  programs.gamemode = {
    enable = true;
    settings = {
      custom = {
        # Allow inner command timeouts plus rollback to finish before GameMode
        # terminates a hook. Each subprocess is bounded by fifteen seconds.
        script_timeout = 150;
        start = "${tools.gaming-mode-hook}/bin/gaming-mode-hook start";
        end = "${tools.gaming-mode-hook}/bin/gaming-mode-hook end";
      };
      # Match executable path fragments, NOT "steam" (which matches steamapps).
      # The inherited preload reaches games; launchers/helpers must not hold a
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
      ExecStart = "${pkgs.systemd}/bin/systemd-inhibit --what=idle --mode=block --who=GameMode --why=Gaming ${inhibitorReady}";
      Restart = "on-failure";
    };
  };
  systemd.user.services.gamemoded.serviceConfig.ExecStopPost =
    "${tools.gaming-mode-hook}/bin/gaming-mode-hook end";
  environment.systemPackages = builtins.attrValues tools;
}
