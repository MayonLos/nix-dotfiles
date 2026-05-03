{ pkgs, ... }:
let
  prismBase = pkgs.prismlauncher.override {
    additionalPrograms = [ pkgs.ffmpeg ];
    jdks = [ pkgs.javaPackages.compiler.temurin-bin.jdk-25 ];
    gamemodeSupport = true;
  };
  # With NVIDIA PRIME offload configured, libglvnd loads NVIDIA EGL first
  # (10_nvidia.json < 50_mesa.json). NVIDIA EGL can't serve a Wayland
  # display in PRIME offload mode and crashes GLFW's EGL context creation.
  # Pin to Mesa EGL so glfw3-minecraft can open a native Wayland window.
  prismWrapped = pkgs.symlinkJoin {
    name = "prismlauncher";
    paths = [ prismBase ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      wrapProgram $out/bin/prismlauncher \
        --set __EGL_VENDOR_LIBRARY_FILENAMES \
          /run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json
    '';
  };
in
{
  home.packages = [ prismWrapped ];
}
