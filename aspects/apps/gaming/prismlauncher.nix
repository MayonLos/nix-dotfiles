{ palette }:
{
  pkgs,
  lib,
  ...
}:

let
  tools = import ./tools.nix { inherit pkgs; };
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
    prismlauncher-unwrapped = pkgs.prismlauncher-unwrapped.overrideAttrs (old: {
      postPatch = (old.postPatch or "") + ''
        # Apply at the game launch boundary, preserving user custom wrappers
        # and instance overrides without rewriting any Prism settings file.
        substituteInPlace launcher/minecraft/launch/LauncherPartLaunch.cpp \
          --replace-fail 'QString wrapperCommandStr = instance->getWrapperCommand().trimmed();' \
          'QString wrapperCommandStr = QStringLiteral("${tools.game-run}/bin/game-run ") + instance->getWrapperCommand().trimmed();'
      '';
    });
    additionalPrograms = [
      pkgs.ffmpeg
      pkgs.mangohud
      pkgs.gamescope
    ];
    # LWJGL 3.4 (lwjgl3ify 3.x, e.g. GTNH 2.9) opens its window through SDL3,
    # which dlopens these for Wayland; without xkbcommon SDL reports
    # "wayland not available". libdecor gives SDL windows their decorations.
    additionalLibs = [
      pkgs.libxkbcommon
      pkgs.libdecor
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
