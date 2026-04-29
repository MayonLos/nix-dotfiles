{
  pkgs,
  pkgs-unstable,
  inputs,
  ...
}:

{
  home.packages = with pkgs; [
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
    pkgs-unstable.github-copilot-cli
    pkgs-unstable.codex
    pkgs-unstable.claude-code

    inputs.MyNixvim.packages.${pkgs.stdenv.hostPlatform.system}.default

    xwayland-satellite
    libnotify
    swww
    mission-center
    bibata-cursors

    wl-clipboard
    cliphist
    xclip

    brightnessctl
    pamixer
    pavucontrol
    playerctl
    obs-studio
    mangohud

    cherry-studio
    wechat
    pkgs-unstable.qq
    pkgs-unstable.go-musicfox

    (prismlauncher.override {
      additionalPrograms = [ ffmpeg ];
      jdks = [
        javaPackages.compiler.temurin-bin.jdk-25
      ];
      gamemodeSupport = true;
    })
  ];
}
