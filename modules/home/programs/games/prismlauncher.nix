{ pkgs, ... }:
{
  home.packages = [
    (pkgs.prismlauncher.override {
      additionalPrograms = [ pkgs.ffmpeg ];
      jdks = with pkgs.javaPackages.compiler.temurin-bin; [
        jdk-8
        jdk-21
        jdk-25
      ];
      gamemodeSupport = true;
    })
  ];
}
