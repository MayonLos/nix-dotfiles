{
  pkgs,
  nixpkgs-unstable,
  MyNixvim,
  quickshell,
  ...
}:

let
  unstable = import nixpkgs-unstable {
    system = "x86_64-linux";
    config.allowUnfree = true;
  };
in

{
  home.packages = with pkgs; [
    fzf
    nodejs
    gcc
    feh
    picom
    dunst
    pamixer
    brightnessctl
    fastfetch
    unzip
    bibata-cursors
    maim
    python315
    gnumake
    mission-center
    networkmanagerapplet

    (prismlauncher.override {
      additionalPrograms = [ ffmpeg ];
      jdks = [
        javaPackages.compiler.temurin-bin.jdk-8
        javaPackages.compiler.temurin-bin.jdk-17
        javaPackages.compiler.temurin-bin.jdk-25
      ];
      gamemodeSupport = true;
    })

    MyNixvim.packages.${pkgs.stdenv.hostPlatform.system}.default
    xwayland-satellite
    fuzzel
    libnotify
    swww
    wl-clipboard
    cliphist
    pavucontrol
    playerctl
    (quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default.withModules [
      pkgs.qt6.qtmultimedia
      pkgs.qt6.qt5compat
    ])
    obs-studio
    ollama
    mangohud
    cherry-studio
    flclash

    unstable.qq
    unstable.go-musicfox
  ];
}
