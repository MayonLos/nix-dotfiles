{ palette }:
{
  pkgs,
  lib,
  ...
}:

let
  java = import ../../../lib/java.nix { inherit pkgs; };
  qtStyle =
    if palette == null then
      null
    else
      import ../../desktop/session-support/qt-style.nix { inherit pkgs palette; };
  prismAddon = pkgs.writeText "one-dark-prism-addon.qss" (
    lib.replaceStrings
      [
        "@BG@"
        "@DEEP@"
        "@SURFACE@"
        "@SELECTION@"
        "@BORDER@"
        "@BLUE@"
        "@FG@"
        "@BRIGHT_FG@"
        "@MUTED@"
        "@ARROW_UP@"
        "@ARROW_DOWN@"
        "@ARROW_UP_DISABLED@"
        "@ARROW_DOWN_DISABLED@"
      ]
      [
        palette.bg
        palette.deep
        palette.surface
        palette.selection
        palette.border
        palette.blue
        palette.fg
        palette.brightFg
        palette.muted
        (toString prismArrowUp)
        (toString prismArrowDown)
        (toString prismArrowUpDisabled)
        (toString prismArrowDownDisabled)
      ]
      (builtins.readFile ./resources/prism/controls.qss)
  );
  prismArrowUp = pkgs.writeText "prism-spin-up.svg" (
    lib.replaceStrings [ "@FG@" ] [ palette.brightFg ] (builtins.readFile ./resources/prism/spin-up.svg)
  );
  prismArrowDown = pkgs.writeText "prism-spin-down.svg" (
    lib.replaceStrings [ "@FG@" ] [ palette.brightFg ] (
      builtins.readFile ./resources/prism/spin-down.svg
    )
  );
  prismArrowUpDisabled = pkgs.writeText "prism-spin-up-disabled.svg" (
    lib.replaceStrings [ "@FG@" ] [ palette.muted ] (builtins.readFile ./resources/prism/spin-up.svg)
  );
  prismArrowDownDisabled = pkgs.writeText "prism-spin-down-disabled.svg" (
    lib.replaceStrings [ "@FG@" ] [ palette.muted ] (builtins.readFile ./resources/prism/spin-down.svg)
  );
  prismStylesheet =
    if palette == null then
      null
    else
      pkgs.runCommand "one-dark-prism.qss"
        {
          baseQss = qtStyle.stylesheet;
          addonQss = prismAddon;
        }
        ''
          cat "$baseQss" > "$out"
          printf '\n' >> "$out"
          cat "$addonQss" >> "$out"
        '';
  prismBackground = pkgs.writeText "prism-flat-background.svg" (
    lib.replaceStrings
      [ "@SURFACE@" "@BORDER@" "@BLUE@" ]
      [ palette.surface palette.border palette.blue ]
      (builtins.readFile ./resources/prism/prism-background.svg)
  );
  prismCatIcon = pkgs.writeText "prism-flat-cat.svg" (
    lib.replaceStrings
      [ "@SURFACE@" "@BORDER@" "@BLUE@" ]
      [ palette.surface palette.border palette.blue ]
      (builtins.readFile ./resources/prism/prism-icon.svg)
  );
  prismlauncher = pkgs.prismlauncher.override {
    additionalPrograms = [
      pkgs.ffmpeg
      pkgs.mangohud
      pkgs.gamescope
    ];
    # Reuse the installed Temurin set; the wrapper exposes these exact store
    # paths through PRISMLAUNCHER_JAVA_PATHS without adding default OpenJDKs.
    jdks = lib.attrValues java.jdks;
    gamemodeSupport = true;
  };
in
{
  home.packages = [ prismlauncher ];
  xdg.dataFile = lib.mkIf (palette != null) {
    "PrismLauncher/themes/OneDark/theme.json".source = qtStyle.themeManifest;
    "PrismLauncher/themes/OneDark/themeStyle.qss".source = prismStylesheet;
    "PrismLauncher/catpacks/NixDotfilesPrism/catpack.json".source = ./resources/prism/catpack.json;
    "PrismLauncher/catpacks/NixDotfilesPrism/prism-background.svg".source = prismBackground;
    "PrismLauncher/iconthemes/NixDotfilesPrism/index.theme".source = ./resources/prism/index.theme;
    "PrismLauncher/iconthemes/NixDotfilesPrism/cat.svg".source = prismCatIcon;
  };
}
