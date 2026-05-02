{
  pkgs,
  pkgs-unstable,
  inputs,
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

    inputs.MyNixvim.packages.${pkgs.stdenv.hostPlatform.system}.default

    xwayland-satellite
    glfw3-minecraft
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

    cherry-studio
    pkgs-unstable.qq
    pkgs-unstable.go-musicfox
  ];
}
