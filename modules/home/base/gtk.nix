{
  pkgs,
  ...
}:

let
  cursorTheme = "Bibata-Modern-Ice";
  cursorSize = 16;
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
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
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
