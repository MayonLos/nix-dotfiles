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
    gnumake
    unzip
    fastfetch
    btop
    pkgs-unstable.github-copilot-cli
    pkgs-unstable.codex
    pkgs-unstable.claude-code

    inputs.MyNixvim.packages.${pkgs.stdenv.hostPlatform.system}.default

    xwayland-satellite
    libnotify
    swww
    mission-center
    wl-clipboard
    xclip

    brightnessctl
    pamixer
    pavucontrol
    playerctl
    mangohud

    cherry-studio
    pkgs-unstable.wechat
    pkgs-unstable.qq
    pkgs-unstable.go-musicfox
  ];
}
