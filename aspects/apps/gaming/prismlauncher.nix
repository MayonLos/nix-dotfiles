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
    "PrismLauncher/themes/OneDark/themeStyle.qss".source = qtStyle.stylesheet;
  };
}
