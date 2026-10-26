{ palette }:
{
  pkgs,
  config,
  lib,
  ...
}:
{
  imports = [ (import ./kde.nix { inherit palette; }) ];
  xdg.configFile."qt6ct/qss/one-dark.qss".source =
    (import ./qt-style.nix { inherit pkgs palette; }).stylesheet;
  # qt6ct owns the mutable GUI configuration and Noctalia owns only the
  # palette file. HM provides a read-only stylesheet and seeds defaults once.
  home.activation =
    let
      seedFile = import ../../../lib/seed-file.nix { inherit lib pkgs; };
      desktop = palette;
      configHome = config.xdg.configHome;
      qt6ctDir = "${configHome}/qt6ct";
      qt6ctConfig = "${qt6ctDir}/qt6ct.conf";
      colorScheme = "${qt6ctDir}/colors/noctalia.conf";
      # qt6ct 0.11's stylesheet picker scans userStyleSheetPath(), which is
      # <config>/qt6ct/qss; keep the HM resource discoverable there.
      stylesheet = "${qt6ctDir}/qss/one-dark.qss";
      # qt6ct 0.11 reads Interface/stylesheets via QSettings as a QStringList.
      # Its INI form is a comma-separated QStringList with QSettings quoting.
      mkConf = pkgs.writeText "qt6ct.conf" ''
        [Appearance]
        color_scheme_path=${colorScheme}
        custom_palette=true
        icon_theme=${desktop.iconTheme}
        standard_dialogs=xdgdesktopportal
        style=Fusion

        # Ten-field QFont serialization uses the legacy normal weight 50.
        [Fonts]
        general="${palette.fonts.sans},11,-1,5,50,0,0,0,0,0"
        fixed="${palette.fonts.mono},11,-1,5,50,0,0,0,0,0"

        [Interface]
        stylesheets=${stylesheet}
      '';
      initialPalette =
        let
          roles = [
            "WindowText"
            "Button"
            "Light"
            "Midlight"
            "Dark"
            "Mid"
            "Text"
            "BrightText"
            "ButtonText"
            "Base"
            "Window"
            "Shadow"
            "Highlight"
            "HighlightedText"
            "Link"
            "LinkVisited"
            "AlternateBase"
            "NoRole"
            "ToolTipBase"
            "ToolTipText"
            "PlaceholderText"
            "Accent"
          ];
          activeColors = {
            WindowText = palette.brightFg;
            Button = palette.surface;
            Light = palette.border;
            Midlight = palette.selection;
            Dark = palette.deep;
            Mid = palette.surface;
            Text = palette.brightFg;
            BrightText = palette.brightFg;
            ButtonText = palette.brightFg;
            Base = palette.deep;
            Window = palette.bg;
            Shadow = palette.black;
            Highlight = palette.selection;
            HighlightedText = palette.brightFg;
            Link = palette.blue;
            LinkVisited = palette.purple;
            AlternateBase = palette.surface;
            NoRole = palette.bg;
            ToolTipBase = palette.surface;
            ToolTipText = palette.brightFg;
            PlaceholderText = palette.fg;
            Accent = palette.blue;
          };
          disabledColors = activeColors // {
            WindowText = palette.fg;
            Text = palette.fg;
            ButtonText = palette.fg;
            HighlightedText = palette.fg;
            Link = palette.fg;
            LinkVisited = palette.fg;
            Accent = palette.fg;
          };
          serialize = colors: lib.concatMapStringsSep ", " (role: colors.${role}) roles;
        in
        pkgs.writeText "qt6ct-initial-palette.conf" ''
          [ColorScheme]
          active_colors=${serialize activeColors}
          disabled_colors=${serialize disabledColors}
          inactive_colors=${serialize activeColors}
        '';
      migrate = pkgs.writeText "qt6ct-migrate.py" (builtins.readFile ./resources/qt/migrate-qt6ct.py);
      safeSeed =
        target: source:
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          if run ${pkgs.python3}/bin/python3 ${migrate} --safe-destination ${lib.escapeShellArg target}; then
            ${seedFile.mkScript target { inherit source; }}
          fi
        '';
    in
    {
      seedQt6ctConfig = safeSeed qt6ctConfig mkConf;
      migrateQt6ctFonts = lib.hm.dag.entryAfter [ "seedQt6ctConfig" ] ''
        run ${pkgs.python3}/bin/python3 ${migrate} ${lib.escapeShellArg qt6ctConfig} ${lib.escapeShellArg stylesheet} ${lib.escapeShellArg desktop.iconTheme} ${lib.escapeShellArg palette.fonts.sans} ${lib.escapeShellArg palette.fonts.mono}
      '';
      seedQt6ctPalette = safeSeed colorScheme initialPalette;
    };
}
