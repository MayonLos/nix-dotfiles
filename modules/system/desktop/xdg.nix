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
        # gnome, not gtk: xdg-desktop-portal-gtk is still GTK 3, which cannot do
        # fractional scaling, so on this 1.5x output its file chooser renders at
        # 1x — noticeably smaller text than the app that opened it — and its
        # client-side shadow sits inside the surface, so niri's focus ring is
        # drawn a shadow's width away from the dialog. The GNOME backend is GTK 4
        # and gets both right.
        "org.freedesktop.impl.portal.FileChooser" = "gnome";
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
