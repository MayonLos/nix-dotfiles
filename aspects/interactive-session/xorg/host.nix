{ pkgs, hostFacts, ... }:
let
  # Greeter resolves this absolute, argument-free client before calling startx.
  # The user's HM profile owns the supervisor, never an arbitrary .xinitrc.
  client = pkgs.writeShellScript "xorg-dwm-session" ''
    exec ${pkgs.systemd}/bin/systemd-cat --identifier=xorg-session --level-prefix=false \
      "''${XDG_DATA_HOME:-$HOME/.local/share}/nix-dotfiles/xorg-session"
  '';
  session =
    pkgs.runCommand "xorg-dwm-session-entry"
      {
        passthru.providedSessions = [ "xorg-dwm" ];
      }
      ''
        mkdir -p "$out/share/xsessions"
        cat > "$out/share/xsessions/xorg-dwm.desktop" <<EOF
        [Desktop Entry]
        Type=Application
        Name=DWM
        Comment=Compatibility desktop with dwm and Picom
        Exec=${client}
        DesktopNames=dwm
        EOF
      '';
in
{
  services.xserver = {
    enable = true;
    dpi = hostFacts.display.x11Dpi;
    displayManager.startx.enable = true;
    # The greeter passes an explicit client; no second session supervisor.
    displayManager.startx.generateScript = false;
  };
  services.libinput.enable = true;
  services.libinput.touchpad = {
    naturalScrolling = true;
    disableWhileTyping = true;
    tapping = true;
    clickMethod = "clickfinger";
  };
  programs.i3lock.enable = true;
  programs.i3lock.package = pkgs.i3lock-color;
  services.displayManager.sessionPackages = [ session ];
  environment.pathsToLink = [ "/share/xsessions" ];
  # Keep the laptop's existing modesetting + NVIDIA PRIME offload policy.
  # Xorg output names are discovered at runtime, not copied from Wayland facts.
  xdg.portal.config.dwm = {
    default = [ "gtk" ];
    "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
    "org.freedesktop.impl.portal.Settings" = [ "gnome" ];
    "org.freedesktop.impl.portal.Secret" = [ "gnome-keyring" ];
    # Neither wlroots nor Mutter capture can serve this Xorg session.
    # Native X11 capture is used by compatible applications instead.
    "org.freedesktop.impl.portal.ScreenCast" = [ "none" ];
    "org.freedesktop.impl.portal.Screenshot" = [ "none" ];
  };
}
