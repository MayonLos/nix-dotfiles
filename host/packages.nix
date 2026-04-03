{
  pkgs,
  pkgs-unstable,
  inputs,
  ...
}:

{
  home.packages = with pkgs; [
    # Core CLI and build tooling
    fzf
    ripgrep
    imagemagick
    nodejs
    clang
    clang-tools
    lld
    (python312.withPackages (
      ps: with ps; [
        pip
      ]
    ))
    python312Packages.uv
    gnumake
    unzip
    fastfetch
    github-copilot-cli
    codex
    claude-code

    # Editor
    inputs.MyNixvim.packages.${pkgs.stdenv.hostPlatform.system}.default

    # Desktop/WM utilities
    xwayland-satellite
    libnotify
    swww
    feh
    mission-center
    bibata-cursors

    # Clipboard and screenshot helpers
    maim
    wl-clipboard
    cliphist
    xclip

    # Audio/media controls and streaming
    brightnessctl
    pamixer
    pavucontrol
    playerctl
    obs-studio
    mangohud

    # Communication and network apps
    cherry-studio
    flclash
    wechat
    pkgs-unstable.qq
    pkgs-unstable.go-musicfox

    # Games / launchers
    (prismlauncher.override {
      additionalPrograms = [ ffmpeg ];
      jdks = [
        javaPackages.compiler.temurin-bin.jdk-8
        javaPackages.compiler.temurin-bin.jdk-17
        javaPackages.compiler.temurin-bin.jdk-21
        javaPackages.compiler.temurin-bin.jdk-25
      ];
      gamemodeSupport = true;
    })
  ];
}
