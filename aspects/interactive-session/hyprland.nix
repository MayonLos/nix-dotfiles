{ palette }:
{
  config,
  lib,
  pkgs,
  hostFacts,
  ...
}:
let
  # Hyprland 0.55 uses native Lua. HM owns both the config and its session
  # target; the host module owns the login entry, portals and GPU policy.
  helpViewer = pkgs.writeShellScript "hyprland-keybindings" ''
    printf '%s\n' "$1" | ${pkgs.less}/bin/less -R
  '';
  desktop = {
    inherit (hostFacts) display;
    inherit (palette)
      bg
      border
      blue
      cyan
      purple
      black
      ;
    reducedMotion = palette.reducedMotion or false;
    inherit (palette) cursor;
    environment = import ../../lib/session-environment.nix {
      inherit lib;
    } config.systemd.user.sessionVariables;
    commands = {
      terminal = "workspace-terminal";
      browser = "workspace-browser";
      files = "workspace-files";
      noctalia = lib.getExe config.programs.noctalia.package;
      playerctl = lib.getExe pkgs.playerctl;
      scratch = "${lib.getExe pkgs.kitty} --class=mayon-scratch";
      scratchFiles = "${lib.getExe pkgs.kitty} --class=mayon-files ${lib.getExe pkgs.yazi}";
      scratchMonitor = "${lib.getExe pkgs.kitty} --class=mayon-monitor ${lib.getExe pkgs.btop}";
      help = "${lib.getExe pkgs.kitty} --class=mayon-hyprland-help --title=Hyprland-keybindings ${helpViewer}";
    };
  };
in
{
  wayland.windowManager.hyprland = {
    enable = true;
    package = pkgs.hyprland;
    # The NixOS module provides the portal, with compositor-specific routing.
    portalPackage = null;
    configType = "lua";
    systemd.enable = true;
    systemd.enableXdgAutostart = false;
    extraConfig = ''
      local desktop = ${lib.generators.toLua { } desktop}
      ${builtins.readFile ./resources/hyprland.lua}
    '';
  };
}
