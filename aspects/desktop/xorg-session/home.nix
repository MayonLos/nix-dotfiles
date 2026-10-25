{ palette }:
{
  config,
  lib,
  pkgs,
  hostFacts,
  ...
}:
let
  target = "xorg-session.target";
  dwmPackage = import ./dwm/package.nix {
    inherit pkgs lib palette;
    profileDirectory = config.home.profileDirectory;
    x11Dpi = hostFacts.display.x11Dpi;
  };
  mkService = import ../../../lib/service.nix;
  guardedUnit = {
    # force: Replace upstream unit defaults with the guarded Xorg session lifecycle.
    PartOf = lib.mkForce [ target ];
    # force: Replace upstream unit defaults with the guarded Xorg session lifecycle.
    After = lib.mkForce [ target ];
    Requisite = [ target ];
    ConditionEnvironment = "XDG_CURRENT_DESKTOP=dwm";
  };
  sessionService =
    description: service:
    mkService {
      inherit description service target;
      unit = {
        Requisite = [ target ];
        ConditionEnvironment = "XDG_CURRENT_DESKTOP=dwm";
      };
    };
in
{
  options.nixDotfiles.xorgDwmPackage = lib.mkOption {
    type = lib.types.package;
    internal = true;
    readOnly = true;
    default = dwmPackage;
    description = "The configured dwm executable used by the Xorg supervisor.";
  };
  imports = [
    (import ./runtime.nix { inherit dwmPackage; })
    (import ./tools.nix { inherit palette; })
    (import ./lock.nix { inherit palette; })
    (import ./ui.nix { inherit palette; })
    (import ./appearance.nix { inherit palette; })
  ];
  config = {
    nixDotfiles.graphicalSessionTargets = [ target ];
    # The explicit greeter entry owns the session; no second .xsession supervisor.
    xsession.enable = false;
    systemd.user.targets.xorg-session.Unit = {
      Description = "Xorg dwm graphical session";
      BindsTo = [ "graphical-session.target" ];
      Wants = [ "graphical-session-pre.target" ];
      After = [ "graphical-session-pre.target" ];
    };
    systemd.user.services = {
      picom = {
        Unit = guardedUnit;
        # force: Replace upstream unit defaults with the guarded Xorg session lifecycle.
        Install.WantedBy = lib.mkForce [ target ];
        # force: Replace upstream unit defaults with the guarded Xorg session lifecycle.
        Service.Restart = lib.mkForce "on-failure";
      };
      dunst = {
        Unit = guardedUnit;
        Install.WantedBy = [ target ];
        Service.Environment = [
          "XDG_DATA_DIRS=${config.services.dunst.iconTheme.package}/share:${pkgs.hicolor-icon-theme}/share:${config.home.profileDirectory}/share:/run/current-system/sw/share"
        ];
      };
      xorg-copyq = sessionService "Xorg clipboard history" {
        ExecStart = "${pkgs.copyq}/bin/copyq";
        Restart = "on-failure";
        RestartSec = 3;
      };
      xorg-polkit = sessionService "Xorg authentication agent" {
        ExecStart = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
        Restart = "on-failure";
        RestartSec = 3;
      };
      xorg-lock = sessionService "Xorg idle and suspend lock" {
        ExecStart = "${pkgs.xss-lock}/bin/xss-lock --transfer-sleep-lock -- ${config.home.profileDirectory}/bin/xorg-lock";
        Restart = "on-failure";
        RestartSec = 3;
      };
      xorg-background = sessionService "Xorg shared wallpaper rotation" {
        ExecStart = "${config.home.profileDirectory}/bin/xorg-wallpaper daemon";
        Restart = "on-failure";
        RestartSec = 3;
      };
      xorg-outputs = sessionService "Xorg display hotplug" {
        ExecStart = "${config.home.profileDirectory}/bin/xorg-outputs";
        Restart = "on-failure";
        RestartSec = 3;
      };
      xorg-idle = sessionService "Xorg idle: lock 15m, screen off 30m, suspend 60m" {
        ExecStartPre = pkgs.writeShellScript "xorg-idle-setup" ''
          ${pkgs.xset}/bin/xset s off
          ${pkgs.xset}/bin/xset dpms 0 0 0
        '';
        # Timers are cumulative. xss-lock owns the actual lock and logind's
        # delay inhibitor; the lock command merely activates XScreenSaver.
        ExecStart = "${pkgs.xidlehook}/bin/xidlehook --not-when-fullscreen --timer 900 '${pkgs.xset}/bin/xset s activate' '' --timer 900 '${pkgs.xset}/bin/xset dpms force off' '' --timer 1800 '${pkgs.systemd}/bin/systemctl suspend' ''";
        Restart = "on-failure";
        RestartSec = 3;
      };
    };
    # HM normally points D-Bus directly at dunst, bypassing the session guard.
    # Use the guarded systemd service even when clients request activation.
    # force: Replace upstream unit defaults with the guarded Xorg session lifecycle.
    xdg.dataFile."dbus-1/services/org.knopwob.dunst.service".source = lib.mkForce (
      pkgs.writeText "org.knopwob.dunst.service" ''
        [D-BUS Service]
        Name=org.freedesktop.Notifications
        Exec=${pkgs.coreutils}/bin/false
        SystemdService=dunst.service
      ''
    );
    home.packages = [
      pkgs.copyq
      pkgs.xss-lock
      pkgs.feh
      pkgs.pavucontrol
      pkgs.xrandr
    ];
  };
}
