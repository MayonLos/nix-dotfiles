{ pkgs, ... }:
{
  home.packages = [
    (pkgs.prismlauncher.override {
      withWaylandGLFW = true;
      additionalPrograms = [ 
        pkgs.ffmpeg
        pkgs.mangohud
        pkgs.gamescope
      ];
      jdks = with pkgs.javaPackages.compiler.temurin-bin; [
        jdk-8
        jdk-17
        jdk-21
        jdk-25
      ];
      gamemodeSupport = true;
    })
  ];
}
