{ pkgs, ... }:
{
  # Both desktops use the keyring Secret service, GTK file chooser and GNOME
  # Settings portal. Capture routing belongs to each session implementation.
  services.gnome.gnome-keyring.enable = true;
  xdg.portal = {
    enable = true;
    extraPortals = [
      pkgs.xdg-desktop-portal-gtk
      pkgs.xdg-desktop-portal-gnome
    ];
  };
}
