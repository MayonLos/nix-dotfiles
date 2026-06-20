{
  pkgs,
  pkgs-unstable,
  inputs,
  lib,
  ...
}:

{
  home.packages = with pkgs; [
    # --- AI / Dev tools (unstable) ---
    pkgs-unstable.github-copilot-cli
    pkgs-unstable.codex
    pkgs-unstable.claude-code

    # --- Neovim (from custom flake input) ---
    inputs.MyNixvim.packages.${pkgs.stdenv.hostPlatform.system}.default

    # --- CLI utilities ---
    fzf
    imagemagick
    nodejs
    fastfetch
    btop
    zoxide
    bat
    eza
    ripgrep
    lazygit
    duf

    # --- Nix tooling ---
    nh
    nix-output-monitor

    # --- Wayland / display ---
    xwayland-satellite
    wl-clipboard
    xclip

    # --- Screenshot & image viewer ---
    grim
    slurp
    satty
    swayimg
    libheif # HEIC/HEIF tools (heif-convert/-enc); swayimg & tumbler already decode .heic

    # --- Audio & hardware control ---
    brightnessctl
    pamixer
    pavucontrol
    playerctl
    libdecor

    # --- Hardware / OEM ---
    lenovo-legion

    # --- Gaming ---
    protonup-qt

    # --- STM32 embedded development ---
    pkgs-unstable.stm32cubemx
    (lib.lowPrio gcc-arm-embedded)
    stlink
    openocd
    dfu-util
    stm32flash

    # --- Personal ---
    obsidian

  ];
}
