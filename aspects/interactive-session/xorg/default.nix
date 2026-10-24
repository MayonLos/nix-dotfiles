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
  mkService = import ../service.nix;
  guardedUnit = {
    PartOf = lib.mkForce [ target ];
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
    ./tools.nix
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
        Install.WantedBy = lib.mkForce [ target ];
        Service.Restart = lib.mkForce "on-failure";
      };
      dunst = {
        Unit = guardedUnit;
        Install.WantedBy = [ target ];
        Service.Environment = [
          "XDG_DATA_DIRS=${pkgs.papirus-icon-theme}/share:${pkgs.hicolor-icon-theme}/share:${config.home.profileDirectory}/share:/run/current-system/sw/share"
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
      xorg-background = sessionService "Xorg wallpaper and screen timeout" {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "xorg-background" ''
          ${pkgs.feh}/bin/feh --no-fehbg --bg-fill ${../resources/wallpaper/wallpaper-005.png}
          ${pkgs.xset}/bin/xset s 600 600
          ${pkgs.xset}/bin/xset dpms 0 0 900
        '';
      };
    };
    # HM normally points D-Bus directly at dunst, bypassing the session guard.
    # Use the guarded systemd service even when clients request activation.
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
