{ palette }:
{
  pkgs,
  lib,
  ...
}:

let
  # One Dark GTK3/GTK4 overrides rendered once at build time. The templates
  # live in resources/gtk/ and are plain Nix string substitutions, so the
  # generated files are the only writer of the managed CSS (no runtime theme
  # renderer rewrites them).
  colorNames = [
    "bg"
    "deep"
    "surface"
    "selection"
    "bright_fg"
    "fg"
    "muted"
    "border"
    "blue"
    "black"
    "red"
    "purple"
  ];
  colorValues = [
    palette.bg
    palette.deep
    palette.surface
    palette.selection
    palette.brightFg
    palette.fg
    palette.muted
    palette.border
    palette.blue
    palette.black
    palette.red
    palette.purple
  ];
  # Pure string substitution at evaluation time: no import-from-derivation and
  # no runtime template engine.
  render =
    path:
    lib.replaceStrings
      (
        [
          "@fontSans@"
          "@fontMono@"
        ]
        ++ map (name: "{{ colors.onedark_${name}_value.default.hex }}") colorNames
      )
      (
        [
          (builtins.toJSON palette.fonts.sans)
          (builtins.toJSON palette.fonts.mono)
        ]
        ++ colorValues
      )
      (builtins.readFile path);
in
{
  home.pointerCursor = {
    package = pkgs.bibata-cursors;
    name = palette.cursor.name;
    size = palette.cursor.size;
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
    # libadwaita geometry stays native; the CSS below supplies its semantics.
    # HM writes gtk-4.0/gtk.css from this block.
    gtk4 = {
      theme = null;
      extraCss = render ./resources/gtk/gtk4.css;
      extraConfig.gtk-enable-animations = !(palette.reducedMotion or false);
    };
    theme = {
      # adw-gtk3-dark is the GTK3 base theme the managed CSS recolors via
      # @define-color overrides (Adwaita-dark does not pick them up cleanly).
      # nwg-look is unnecessary -- HM sets this declaratively.
      name = "adw-gtk3-dark";
      package = pkgs.adw-gtk3;
    };
    iconTheme = {
      name = palette.iconTheme;
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
    # HM writes gtk-3.0/gtk.css from this block.
    gtk3 = {
      extraCss = render ./resources/gtk/gtk3.css;
      extraConfig.gtk-enable-animations = !(palette.reducedMotion or false);
    };
  };

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      icon-theme = palette.iconTheme;
      enable-animations = !(palette.reducedMotion or false);
    };
  };
}
