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
  # seeds, not ongoing writers: preserve qt6ct GUI settings and let Noctalia
  # keep updating its existing mutable palette path when that shell is selected.
  # Neither file is owned through a Home Manager symlink.
  home.activation =
    let
      seedFile = import ../../lib/seed-file.nix { inherit lib pkgs; };
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
        Base = palette.bg;
        Window = palette.bg;
        Shadow = palette.black;
        Highlight = palette.blue;
        HighlightedText = palette.black;
        Link = palette.blue;
        LinkVisited = palette.purple;
        AlternateBase = palette.surface;
        NoRole = palette.bg;
        ToolTipBase = palette.surface;
        ToolTipText = palette.brightFg;
        PlaceholderText = palette.muted;
        Accent = palette.blue;
      };
      disabledColors = activeColors // {
        WindowText = palette.muted;
        Text = palette.muted;
        ButtonText = palette.muted;
        Highlight = palette.selection;
        HighlightedText = palette.muted;
        Link = palette.muted;
        LinkVisited = palette.muted;
        Accent = palette.muted;
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
      seed =
        name:
        seedFile.mkActivation "${config.xdg.configHome}/${name}/${name}.conf" {
          source = mkConf name;
        };
    in
    {
      seedQt6ctConfig = seed "qt6ct";
      seedQt6ctPalette = seedFile.mkActivation colorScheme { source = initialPalette; };
    };
}
