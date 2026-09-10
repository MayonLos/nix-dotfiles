{ pkgs, ... }:
{
  # Two things used to arrive for free with `programs.niri.enable` and have to
  # be asked for by name now that mango is the only compositor:
  #
  #   * xdg-desktop-portal-gnome, which niri's module added to extraPortals.
  #   * gnome-keyring, which niri's module switched on via
  #     services.gnome.gnome-keyring.enable. That is not just a portal -- it is
  #     the Secret Service every application stores passwords in. mango's own
  #     module routes org.freedesktop.impl.portal.Secret at gnome-keyring but
  #     never enables it, so dropping this line leaves the Secret portal
  #     pointing at a backend that is not running.
  services.gnome.gnome-keyring.enable = true;

  xdg.portal = {
    enable = true;

    # mango's module contributes xdg-desktop-portal-wlr and -gtk. The GNOME
    # backend is added here for the file chooser alone: xdg-desktop-portal-gtk
    # is still GTK 3, which cannot do fractional scaling, so on this 1.5x output
    # its file chooser renders at 1x -- noticeably smaller text than the app
    # that opened it -- and its client-side shadow sits inside the surface, so
    # the compositor's border is drawn a shadow's width away from the dialog.
    # The GNOME backend is GTK 4 and gets both right.
    extraPortals = [ pkgs.xdg-desktop-portal-gnome ];

    config.mango = {
      # Only keys mango's own module leaves unset appear here; it already fixes
      # `default`, Secret, ScreenCast, Screenshot and Inhibit, and setting any
      # of those again would collide rather than override.
      #
      # ScreenCast and Screenshot in particular must stay on wlr and are
      # deliberately not listed: niri implemented org.gnome.Mutter.ScreenCast,
      # which is why they pointed at the GNOME backend before. mango is plain
      # wlroots and has no such interface, so capture goes through
      # xdg-desktop-portal-wlr, which picks its region with slurp.
      "org.freedesktop.impl.portal.FileChooser" = "gnome";
      "org.freedesktop.impl.portal.Settings" = "gnome";
      "org.freedesktop.impl.portal.OpenURI" = "gtk";
    };

    config.common.default = "gnome";
  };
}
