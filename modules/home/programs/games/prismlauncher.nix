{ pkgs, pkgs-unstable, ... }:
{
  home.packages = [
    (pkgs.prismlauncher.override {
      additionalPrograms = [
        pkgs.ffmpeg
        pkgs.mangohud
        pkgs.gamescope
      ];
      jdks =
        (with pkgs.javaPackages.compiler.temurin-bin; [
          jdk-8
          jdk-17
          jdk-21
          jdk-25
        ])
        # 26 is not in stable 26.05 yet.
        ++ [ pkgs-unstable.javaPackages.compiler.temurin-bin.jdk-26 ];
      gamemodeSupport = true;
    })
  ];
}
