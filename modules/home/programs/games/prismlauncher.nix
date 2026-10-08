{
  pkgs,
  pkgs-unstable,
  lib,
  ...
}:

let
  java = import ../../../../lib/java.nix { inherit pkgs pkgs-unstable; };
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
}
