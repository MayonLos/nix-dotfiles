{
  pkgs,
  home,
  palette,
}:
let
  inherit (pkgs) lib;
  python = pkgs.python3.withPackages (p: [
    p.pygobject3
    p.tinycss2
  ]);
  assets = lib.removePrefix "NOCTALIA_ASSETS_DIR=" (
    lib.findFirst (lib.hasPrefix "NOCTALIA_ASSETS_DIR=")
      (throw "GTK check requires the selected Noctalia asset bundle")
      home.systemd.user.services.noctalia.Service.Environment
  );
  customColors = (pkgs.formats.toml { }).generate "gtk-qt-custom-colors.toml" {
    config.custom_colors = home.programs.noctalia.settings.theme.templates.custom_colors;
  };
  theme = pkgs.writeText "gtk-qt-theme.json" (
    builtins.toJSON {
      dark = home.programs.noctalia.customPalettes.onedark.dark;
    }
  );
  paletteJson = pkgs.writeText "gtk-qt-palette.json" (builtins.toJSON palette);
  replaceConfig = lib.replaceStrings [ home.xdg.configHome ] [ "$XDG_CONFIG_HOME" ];
  qtSeed = pkgs.writeText "qt-theme-seed.sh" (
    replaceConfig home.home.activation.seedQt6ctConfig.data
  );
  qtMigration = pkgs.writeText "qt-theme-migrate.sh" (
    replaceConfig home.home.activation.migrateQt6ctFonts.data
  );
  qss = home.xdg.configFile."qt6ct/qss/one-dark.qss".source;
in
assert home.gtk.theme.name == "adw-gtk3-dark";
assert home.gtk.iconTheme.name == palette.iconTheme;
assert palette.iconTheme == "Tela-circle-dark";
assert home.dconf.settings."org/gnome/desktop/interface".icon-theme == palette.iconTheme;
assert !(home.xdg.configFile ? "gtk-3.0/gtk.css");
assert !(home.xdg.configFile ? "gtk-4.0/gtk.css");
pkgs.runCommand "gtk-qt-theme-check" {
  NOCTALIA = lib.getExe home.programs.noctalia.package;
  ASSETS = assets;
  THEME_JSON = theme;
  CUSTOM_COLORS = customColors;
  PALETTE_JSON = paletteJson;
  CHECK_CSS = ./resources/gtk/check-css.py;
  QSS_SOURCE = qss;
  QT_SEED = qtSeed;
  QT_MIGRATION = qtMigration;
  GTK_THEME_PACKAGE = home.gtk.theme.package;
  GTK_THEME_NAME = home.gtk.theme.name;
  ICON_PACKAGE = home.gtk.iconTheme.package;
  ICON_NAME = home.gtk.iconTheme.name;
  PRODUCTION_CONFIG_HOME = home.xdg.configHome;
  EXPECTED_SANS = "${palette.fonts.sans},11,-1,5,50,0,0,0,0,0";
  EXPECTED_MONO = "${palette.fonts.mono},11,-1,5,50,0,0,0,0,0";
  FONTCONFIG_FILE = pkgs.makeFontsConf {
    fontDirectories = [
      pkgs.inter
      pkgs.maple-mono.NF-CN
    ];
  };
  nativeBuildInputs = [
    python
    pkgs.gobject-introspection
    pkgs.pkg-config
    pkgs.stdenv.cc
  ];
  buildInputs = [
    pkgs.gtk3
    pkgs.gtk4
    pkgs.qt6Packages.qtbase
  ];
} "bash ${./resources/gtk/check-theme.sh}"
