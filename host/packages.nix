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

    inputs.MyNixvim.packages.${pkgs.stdenv.hostPlatform.system}.default
    xwayland-satellite
    fuzzel
    libnotify
    swww
    wl-clipboard
    cliphist
    pavucontrol
    playerctl
    obs-studio
    mangohud
    cherry-studio
    flclash
    wechat
    xclip

    unstable.qq
    unstable.go-musicfox
  ];
}
