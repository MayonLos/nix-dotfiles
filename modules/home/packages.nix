{
  pkgs,
  pkgs-unstable,
  inputs,
  lib,
  ...
}:

{
  home.packages = with pkgs; [
    fzf
    imagemagick
    nodejs
    obsidian
    fastfetch
    btop
    pkgs-unstable.github-copilot-cli
    pkgs-unstable.codex
    pkgs-unstable.claude-code
    pkgs-unstable.gemini-cli

    lenovo-legion

    # 现代 CLI 工具
    zoxide
    bat
    eza
    ripgrep
    lazygit
    duf
    nh
    nix-output-monitor

    inputs.MyNixvim.packages.${pkgs.stdenv.hostPlatform.system}.default

    xwayland-satellite
    mission-center
    wl-clipboard
    xclip

    grim
    slurp
    satty
    swayimg

    brightnessctl
    pamixer
    pavucontrol
    playerctl
    mangohud
    libdecor

    cherry-studio
    pkgs-unstable.qq
    pkgs-unstable.go-musicfox

    # STM32 embedded development
    pkgs-unstable.stm32cubemx
    (lib.lowPrio gcc-arm-embedded)
    stlink
    openocd
    dfu-util
    stm32flash
  ];
}
