{ dwmPackage }:
{
  config,
  pkgs,
  lib,
  ...
}:

let
  supervisor = pkgs.replaceVars ./session {
    runtimeShell = "${pkgs.bash}/bin/bash";
    dbusUpdateActivationEnvironment = "${pkgs.dbus}/bin/dbus-update-activation-environment";
    hmSessionVars = "${config.home.profileDirectory}/etc/profile.d/hm-session-vars.sh";
    dwm = "${dwmPackage}/bin/dwm";
    sleep = "${pkgs.coreutils}/bin/sleep";
    stat = "${pkgs.coreutils}/bin/stat";
    systemctl = "${pkgs.systemd}/bin/systemctl";
    xprop = "${pkgs.xprop}/bin/xprop";
    defaultXModifiers = lib.escapeShellArg (config.systemd.user.sessionVariables.XMODIFIERS or "");
    defaultOzone = lib.escapeShellArg (config.systemd.user.sessionVariables.NIXOS_OZONE_WL or "");
  };
  exitCommand = pkgs.writeShellApplication {
    name = "xorg-session-exit";
    text = ''
      exec ${pkgs.bash}/bin/bash ${supervisor} --exit
    '';
  };
in
{
  home.packages = [ exitCommand ];

  xdg.dataFile."nix-dotfiles/xorg-session" = {
    source = supervisor;
    executable = true;
  };
}
