{ pkgs, lib, ... }:

let
  # `jdks = [ ]` leaves lib.makeSearchPath with an empty value, and
  # wrapQtAppsHook word-splits the serialized qtWrapperArgs, so the following
  # `--set` would be consumed as the prefix value and the wrapper build fails.
  # Drop that one prefix instead; Prism detects the `java` on PATH (Temurin,
  # via session-vars.nix) by itself.
  prismlauncher =
    (pkgs.prismlauncher.override {
      additionalPrograms = [
        pkgs.ffmpeg
        pkgs.mangohud
        pkgs.gamescope
      ];
      jdks = [ ];
      gamemodeSupport = true;
    }).overrideAttrs
      (old: {
        qtWrapperArgs = builtins.filter (
          arg: !(lib.hasPrefix "--prefix PRISMLAUNCHER_JAVA_PATHS" arg)
        ) old.qtWrapperArgs;
      });
in
{
  home.packages = [ prismlauncher ];
}
