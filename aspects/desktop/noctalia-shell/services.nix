{
  config,
  lib,
  pkgs,
  ...
}:
let
  targets = [
    "mango-session.target"
    "umbriel-session.target"
    "hyprland-session.target"
  ];
  noctalia = "${pkgs.local.noctaliaDesktop.noctalia}/bin/noctalia";
  polkitAgent = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
  clipboardBridge = import ./clipboard-bridge.nix { inherit pkgs; };
  # Compositors import WAYLAND_DISPLAY/XDG_SESSION_TYPE into the user manager
  # before starting their session target, so a service WantedBy every target
  # gets the same environment in all three sessions.
  shellPath = "${config.home.profileDirectory}/bin:/run/current-system/sw/bin";
  configuredFiles = builtins.attrNames config.xdg.configFile;
  restartFiles = map (name: config.xdg.configFile.${name}.source) (
    builtins.filter (name: lib.hasPrefix "noctalia/" name) configuredFiles
  );
in
{
  systemd.user.services = {
    noctalia = {
      Unit = {
        Description = "Noctalia Wayland desktop shell";
        Documentation = [ "https://docs.noctalia.dev/v5/" ];
        PartOf = targets;
        After = targets;
        X-Restart-Triggers = restartFiles;
      };
      Service = {
        Type = "notify";
        ExecStart = noctalia;
        Restart = "on-failure";
        RestartSec = 2;
        Environment = [ "PATH=${shellPath}" ];
      };
      Install.WantedBy = targets;
    };

    # The repository's polkit agent used to be bound to mango-session.target.
    # Noctalia's own agent cannot register this session's logind identity, so
    # the standalone agent runs in every session instead.
    polkit-gnome-authentication-agent-1 = {
      Unit = {
        Description = "polkit authentication agent";
        PartOf = targets;
        After = targets;
        StartLimitIntervalSec = 60;
        StartLimitBurst = 3;
      };
      Service = {
        ExecCondition = "${pkgs.runtimeShell} -c '[ -n \"$WAYLAND_DISPLAY\" ]'";
        ExecStart = polkitAgent;
        Restart = "on-failure";
        RestartSec = 2;
      };
      Install.WantedBy = targets;
    };

    # XWayland and Wayland keep separate selections on this host; the bridge is
    # part of the session contract, not of a particular desktop shell.
    clipboard-bridge = {
      Unit = {
        Description = "Clipboard bridge between Wayland and X11";
        PartOf = targets;
        After = targets;
        StartLimitIntervalSec = 60;
        StartLimitBurst = 3;
      };
      Service = {
        ExecStart = "${clipboardBridge}/bin/clipboard-bridge bridge";
        Restart = "always";
        RestartSec = 2;
        UnsetEnvironment = [ "LC_ALL" ];
      };
      Install.WantedBy = targets;
    };
  };
}
