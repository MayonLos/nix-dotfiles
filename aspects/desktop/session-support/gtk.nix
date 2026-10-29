{ palette }:
{
  pkgs,
  config,
  lib,
  ...
}:

let
  desktop = palette;
  noctaliaPaletteColors = {
    onedark_bg = palette.bg;
    onedark_deep = palette.deep;
    onedark_surface = palette.surface;
    onedark_selection = palette.selection;
    onedark_bright_fg = palette.brightFg;
    onedark_fg = palette.fg;
    onedark_muted = palette.muted;
    onedark_border = palette.border;
    onedark_blue = palette.blue;
    onedark_black = palette.black;
    onedark_red = palette.red;
    onedark_purple = palette.purple;
  };
  noctaliaAssets = import ./resources.nix {
    inherit pkgs palette;
    package = config.programs.noctalia.package;
  };
in
lib.mkMerge [
  {
    home.pointerCursor = {
      package = pkgs.bibata-cursors;
      name = desktop.cursor.name;
      size = desktop.cursor.size;
      gtk.enable = true;
      # x11.enable is what emits Xcursor.theme / Xcursor.size into
      # xresources.properties, which xresources.nix merges into the running
      # Xwayland server -- that is the half that reaches XWayland clients.
      # x11.defaultCursor is deliberately left at its default: it names a cursor
      # *file* inside share/icons/<theme>/cursors/ (left_ptr), not the theme, and
      # it is only ever used by xsession.profileExtra, which mango never runs.
      x11.enable = true;
    };

    gtk = {
      enable = true;
      font = {
        name = palette.fonts.sans;
        # GTK stores points; 10.5 pt is 14 logical px at 96 DPI.
        size = 10.5;
      };
      # Keep libadwaita geometry; Noctalia supplies semantic GTK4 colors.
      gtk4.theme = null;
      theme = {
        # adw-gtk3-dark is the GTK3 theme Noctalia's gtk template is designed to recolor
        # via the generated ~/.config/gtk-3.0/gtk.css (Adwaita-dark doesn't pick up those
        # @define-color overrides cleanly). nwg-look is unnecessary — HM sets this declaratively.
        name = "adw-gtk3-dark";
        package = pkgs.adw-gtk3;
      };
      iconTheme = {
        name = desktop.iconTheme;
        # WhiteSur's default folder artwork is blue; the dark install is named
        # WhiteSur-dark. themeVariants controls alternate accent colors.
        package = pkgs.whitesur-icon-theme;
      };
      # adw-gtk3 has no GTK2 resources. Legacy applications need an actual
      # GTK2 engine before the shared color roles can take effect.
      gtk2 = {
        theme = {
          name = "Adwaita-dark";
          package = pkgs.gnome-themes-extra;
        };
        extraConfig = ''
          style "nix-dotfiles-one-dark" {
            bg[NORMAL] = "${palette.bg}"
            bg[ACTIVE] = "${palette.surface}"
            bg[PRELIGHT] = "${palette.surface}"
            bg[SELECTED] = "${palette.selection}"
            bg[INSENSITIVE] = "${palette.bg}"
            fg[NORMAL] = "${palette.brightFg}"
            fg[ACTIVE] = "${palette.brightFg}"
            fg[PRELIGHT] = "${palette.brightFg}"
            fg[SELECTED] = "${palette.brightFg}"
            fg[INSENSITIVE] = "${palette.muted}"
            base[NORMAL] = "${palette.deep}"
            base[SELECTED] = "${palette.selection}"
            text[NORMAL] = "${palette.brightFg}"
            text[SELECTED] = "${palette.brightFg}"
          }
          class "*" style "nix-dotfiles-one-dark"
        '';
      };
      gtk3.extraConfig.gtk-enable-animations = !(palette.reducedMotion or false);
      gtk4.extraConfig.gtk-enable-animations = !(palette.reducedMotion or false);
    };

    dconf.settings = {
      "org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
        icon-theme = desktop.iconTheme;
        enable-animations = !(palette.reducedMotion or false);
      };
    };

    # Noctalia renders GTK/Qt files through its own template lifecycle. Point
    # that existing writer at a complete copy of the final package's assets,
    # replacing only the three palette templates. The option guard keeps this
    # shared support aspect usable by Xorg sessions without Noctalia installed.
  }
  (lib.mkIf (config.programs.noctalia.enable or false) {
    systemd.user.services.noctalia.Service.Environment = [ "NOCTALIA_ASSETS_DIR=${noctaliaAssets}" ];

    programs.noctalia.settings.theme.templates.custom_colors = lib.mapAttrs (_: color: {
      inherit color;
      blend = false;
    }) noctaliaPaletteColors;
  })
]
