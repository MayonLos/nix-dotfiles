{ palette }:
{
  pkgs,
  lib,
  ...
}:
let
  stack = pkgs.local.noctaliaDesktop;
  umbrielLogin = pkgs.writeShellScript "umbriel-login" ''
    export XDG_SESSION_TYPE=wayland
    export XDG_CURRENT_DESKTOP=Umbriel
    export XDG_SESSION_DESKTOP=umbriel
    export XKB_DEFAULT_LAYOUT=us
    export XCURSOR_THEME=${palette.cursor.name}
    export XCURSOR_SIZE=${toString palette.cursor.size}
    exec ${stack.umbriel}/bin/start-umbriel
  '';
in
{
  # start-umbriel enters the login shell once, imports the environment into
  # the user manager and starts umbriel.service; the compositor package brings
  # its user units (umbriel.service, umbriel-session.target).
  systemd.packages = [ stack.umbriel ];

  environment.systemPackages = [
    stack.umbriel
    stack.noctalia
    stack.luciole
    stack.portal
  ];

  xdg.portal = {
    enable = lib.mkDefault true;
    extraPortals = [ stack.portal ];
    # The experiment session prefers Umbriel's portal backend; the GTK backend
    # stays as the fallback for interfaces it does not implement.
    config.umbriel = {
      default = "umbriel;gtk";
      "org.freedesktop.impl.portal.FileChooser" = "gtk";
    };
  };

  nixDotfiles.extraLoginCommands = [
    {
      name = "Umbriel + Noctalia";
      command = "${umbrielLogin}";
    }
  ];
}
