{
  pkgs,
  ...
}:

let
  cursorTheme = "Bibata-Modern-Ice";
  cursorSize = 24;
in
{
  home.pointerCursor = {
    package = pkgs.bibata-cursors;
    name = cursorTheme;
    size = cursorSize;
    x11.defaultCursor = cursorTheme;
    gtk.enable = true;
    x11.enable = true;
  };

  gtk = {
    enable = true;
    # GTK4/libadwaita stays unthemed → reads Noctalia's generated ~/.config/gtk-4.0/gtk.css
    gtk4.theme = null;
    theme = {
      # adw-gtk3-dark is the GTK3 theme Noctalia's gtk template is designed to recolor
      # via the generated ~/.config/gtk-3.0/gtk.css (Adwaita-dark doesn't pick up those
      # @define-color overrides cleanly). nwg-look is unnecessary — HM sets this declaratively.
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    iconTheme = {
      name = "Papirus-Dark";
      package = pkgs.papirus-icon-theme;
    };
  };

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
  };
}
