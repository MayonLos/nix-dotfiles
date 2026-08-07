_: {
  xdg.portal = {
    # No `extraPortals` here on purpose: `programs.niri.enable` already pulls in
    # xdg-desktop-portal-gnome, and gtk + gnome-keyring come along with it.
    # Listing them again (plus the xdg-desktop-portal host package, which is not
    # a backend) duplicated every backend and produced a stream of
    # "Ignoring duplicate name org.freedesktop.portal.Desktop" from dbus-broker.
    enable = true;

    config = {
      niri = {
        default = [
          "gnome"
          "gtk"
        ];
        "org.freedesktop.impl.portal.FileChooser" = "gtk";
        "org.freedesktop.impl.portal.ScreenCast" = "gnome";
        "org.freedesktop.impl.portal.Screenshot" = "gnome";
        "org.freedesktop.impl.portal.OpenURI" = "gtk";
        "org.freedesktop.impl.portal.Settings" = "gnome";
        "org.freedesktop.impl.portal.Inhibit" = "gnome";
      };

      common.default = "gnome";
    };
  };
}
