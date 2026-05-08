{ pkgs, ... }:
let
  prismBase = pkgs.prismlauncher.override {
    additionalPrograms = [ pkgs.ffmpeg ];
    jdks = [ pkgs.javaPackages.compiler.temurin-bin.jdk-25 ];
    gamemodeSupport = true;
  };
  prismWrapped = pkgs.symlinkJoin {
    name = "prismlauncher";
    paths = [ prismBase ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/prismlauncher \
        --set __EGL_VENDOR_LIBRARY_FILENAMES \
          /run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json \
        --set ZINK_PERF_RELAX 1 \
        --set MESA_NO_ERROR 1
    '';
  };
in
{
  home.packages = [ prismWrapped ];
}
