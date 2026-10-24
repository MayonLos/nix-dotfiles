{ palette }:
{
  pkgs,
  config,
  lib,
  ...
}:
{
  # qt6ct needs both its configuration and a color scheme on a fresh account,
  # including Xorg-only accounts that never run Noctalia. These are initial
  # seeds with a bounded migration of the former repository font defaults:
  # preserve all other qt6ct GUI settings and let Noctalia
  # keep updating its existing mutable palette path when that shell is selected.
  # Neither file is owned through a Home Manager symlink.
  home.activation =
    let
      seedFile = import ../../../lib/seed-file.nix { inherit lib pkgs; };
      desktop = palette;
      colorScheme = "${config.xdg.configHome}/qt6ct/colors/noctalia.conf";
      # The locked Noctalia assets/templates/qt/qtct.conf uses these 22 slots.
      # Qt 6.11 QPalette::ColorRole fixes their serialization order, including
      # NoRole at index 17 and Accent at 21; retain every slot.
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
        Highlight = palette.selection;
        HighlightedText = palette.fg;
        Link = palette.fg;
        LinkVisited = palette.fg;
        Accent = palette.fg;
      };
      serializeColors = colors: lib.concatMapStringsSep ", " (role: colors.${role}) roles;
      initialPalette = pkgs.writeText "qt6ct-initial-palette.conf" ''
        [ColorScheme]
        active_colors=${serializeColors activeColors}
        disabled_colors=${serializeColors disabledColors}
        inactive_colors=${serializeColors activeColors}
      '';
      mkConf =
        name:
        pkgs.writeText "${name}.conf" ''
          [Appearance]
          color_scheme_path=${colorScheme}
          custom_palette=true
          icon_theme=${desktop.iconTheme}
          standard_dialogs=default
          style=Fusion

          [Fonts]
          general=${palette.fonts.sans},11,-1,5,400,0,0,0,0,0
          fixed=${palette.fonts.mono},11,-1,5,400,0,0,0,0,0
        '';
      migrateFonts = pkgs.writeText "qt6ct-migrate-fonts.py" ''
        import re
        import sys
        from pathlib import Path

        path = Path(sys.argv[1])
        if not path.is_file() or path.is_symlink():
            sys.exit(0)
        # Match the complete former seeds, including size and weight. A GUI
        # choice with different metrics or another family remains user-owned.
        replacements = {
            "general=Noto Sans CJK SC,11,-1,5,400,0,0,0,0,0": "general=${palette.fonts.sans},11,-1,5,400,0,0,0,0,0",
            "fixed=JetBrainsMono Nerd Font,11,-1,5,400,0,0,0,0,0": "fixed=${palette.fonts.mono},11,-1,5,400,0,0,0,0,0",
        }
        text = path.read_text()
        lines = text.splitlines(keepends=True)
        section = ""
        for index, line in enumerate(lines):
            match = re.fullmatch(r"\[([^]]+)\]", line.strip())
            if match:
                section = match[1]
            if section == "Fonts" and line.rstrip("\n") in replacements:
                lines[index] = replacements[line.rstrip("\n")] + ("\n" if line.endswith("\n") else "")
        result = "".join(lines)
        if result != text:
            path.write_text(result)
      '';
      seed =
        name:
        seedFile.mkActivation "${config.xdg.configHome}/${name}/${name}.conf" {
          source = mkConf name;
        };
      qt6ctConfig = "${config.xdg.configHome}/qt6ct/qt6ct.conf";
    in
    {
      seedQt6ctConfig = seed "qt6ct";
      migrateQt6ctFonts = lib.hm.dag.entryAfter [ "seedQt6ctConfig" ] ''
        qt6ct_config=${lib.escapeShellArg qt6ctConfig}
        if [ -f "$qt6ct_config" ] && [ ! -L "$qt6ct_config" ] && {
          grep -Fq -- 'general=Noto Sans CJK SC,11,-1,5,400,0,0,0,0,0' "$qt6ct_config" ||
          grep -Fq -- 'fixed=JetBrainsMono Nerd Font,11,-1,5,400,0,0,0,0,0' "$qt6ct_config"
        }; then
          run ${pkgs.python3}/bin/python3 ${migrateFonts} "$qt6ct_config"
        fi
      '';
      seedQt6ctPalette = seedFile.mkActivation colorScheme { source = initialPalette; };
    };
}
