{ pkgs, ... }:
{
  home.packages = [
    (pkgs.prismlauncher.override {
      additionalPrograms = [ pkgs.ffmpeg ];
      jdks = [
        pkgs.javaPackages.compiler.temurin-bin.jdk-25
      ];
      gamemodeSupport = true;
    })
  ];
}
