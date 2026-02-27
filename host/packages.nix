{
  pkgs,
  inputs,
  ...
}:

let
  unstable = import inputs.nixpkgs-unstable {
    system = "x86_64-linux";
    config.allowUnfree = true;
  };
in

{
  home.packages = with pkgs; [
    # Core CLI and build tooling
    fzf
    nodejs
    gcc
    python315
    gnumake
    unzip
    fastfetch

    # Editor
    inputs.MyNixvim.packages.${pkgs.stdenv.hostPlatform.system}.default

    # Desktop/WM utilities
    xwayland-satellite
    fuzzel
    libnotify
    swww
    feh
    picom
    dunst
    mission-center
    networkmanagerapplet
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
    unstable.qq
    unstable.go-musicfox

    # Games / launchers
    (prismlauncher.override {
      additionalPrograms = [ ffmpeg ];
      jdks = [
        javaPackages.compiler.temurin-bin.jdk-8
        javaPackages.compiler.temurin-bin.jdk-17
        javaPackages.compiler.temurin-bin.jdk-25
      ];
      gamemodeSupport = true;
    })
  ];
}
