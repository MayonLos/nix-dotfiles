{
  pkgs,
  home,
  palette,
}:
let
  inherit (pkgs) lib;
  assets = lib.removePrefix "NOCTALIA_ASSETS_DIR=" (
    lib.findFirst (lib.hasPrefix "NOCTALIA_ASSETS_DIR=")
      (throw "Template CLI check requires the production Noctalia asset bundle")
      home.systemd.user.services.noctalia.Service.Environment
  );
  metadata = pkgs.writeText "noctalia-template-inputs.json" (
    builtins.toJSON {
      templates = home.programs.noctalia.settings.theme.templates;
      inherit palette;
    }
  );
  theme = pkgs.writeText "noctalia-template-palette.json" (
    builtins.toJSON {
      dark = home.programs.noctalia.customPalettes.onedark.dark;
    }
  );
in
pkgs.runCommand "noctalia-template-cli-runtime"
  {
    nativeBuildInputs = [
      (pkgs.python3.withPackages (p: [ p.tomlkit ]))
      pkgs.bash
      pkgs.coreutils
      pkgs.gawk
    ];
    NOCTALIA = lib.getExe home.programs.noctalia.package;
    NOCTALIA_ASSETS_DIR = assets;
    INPUTS = metadata;
    THEME_JSON = theme;
    MAIN_CONFIG = home.xdg.configFile."noctalia/config.toml".source;
    RAW_GTK3 = ./resources/gtk/gtk3.css;
    RAW_GTK4 = ./resources/gtk/gtk4.css;
    RAW_QT = ./resources/qt/qtct.conf;
  }
  ''
    unset DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS SWAYSOCK
    export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/config" XDG_CACHE_HOME="$TMPDIR/cache" XDG_DATA_HOME="$TMPDIR/data" XDG_STATE_HOME="$TMPDIR/state"
    export XDG_RUNTIME_DIR="$TMPDIR/runtime" GSETTINGS_BACKEND=keyfile
    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR" "$out"
    python3 ${./resources/gtk/check-template-runtime.py}
  ''
