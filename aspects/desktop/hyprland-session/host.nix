{ palette }:
{
  pkgs,
  lib,
  config,
  ...
}:
let
  # gtkgreet passes one argv element and enforces <128 bytes with no spaces,
  # so the whole session setup lives in a script. Hyprland needs the same
  # session identity the other two sessions export; start-hyprland resolves
  # "Hyprland" through PATH, so /run/wrappers/bin must come first: that is the
  # setcap wrapper the stable NixOS module creates for SCHED_RR (without it
  # Hyprland logs "Failed to change process scheduling strategy").
  hyprlandLogin = pkgs.writeShellScript "hyprland-login" ''
    export XDG_SESSION_TYPE=wayland
    export XDG_CURRENT_DESKTOP=Hyprland
    export XDG_SESSION_DESKTOP=hyprland
    export XKB_DEFAULT_LAYOUT=us
    export SHELL=/run/current-system/sw/bin/zsh
    export PATH="/run/wrappers/bin:/run/current-system/sw/bin:$HOME/.nix-profile/bin:$PATH"
    export XCURSOR_THEME=${palette.cursor.name}
    export XCURSOR_SIZE=${toString palette.cursor.size}
    exec ${config.programs.hyprland.package}/bin/start-hyprland
  '';
in
{
  # Stable nixpkgs (Hyprland 0.55.4, hyprlang era). The module installs the
  # compositor, its Wayland session entry and xdg-desktop-portal-hyprland, so
  # the host side needs no parallel portal wiring. UWSM stays off: the HM
  # module's systemd integration starts hyprland-session.target itself and
  # adding uwsm would introduce a second session manager.
  programs.hyprland = {
    enable = true;
    withUWSM = false;
    xwayland.enable = true;
  };

  # Per-desktop routing for the hyprland session: upstream portal for the
  # interfaces it implements, GTK as the fallback (FileChooser, Settings).
  xdg.portal.config.hyprland = {
    default = "hyprland;gtk";
  };

  nixDotfiles.extraLoginCommands = [
    {
      name = "hyprland";
      command = "${hyprlandLogin}";
    }
  ];
}
