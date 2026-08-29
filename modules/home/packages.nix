{
  pkgs,
  pkgs-unstable,
  ...
}:

{
  home.packages = with pkgs; [
    qt6Packages.qt6ct
    pkgs-unstable.github-copilot-cli
    # codex comes from programs/dev/codex — wrapped to default to DeepSeek.
    pkgs-unstable.claude-code
    # dsh, opencode and zcode come from programs/dev/ai-agents.nix — they are
    # packaged by the llm-agents.nix input, not by nixpkgs.
    # nvim comes from programs/dev/nvim.nix — built from ./nixvim in this repo.
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
    nix-output-monitor
    wl-clipboard
    xclip
    grim
    slurp
    swayimg
    libheif
    brightnessctl
    pamixer
    pavucontrol
    playerctl
    libdecor
    lenovo-legion
    protonup-qt
    obsidian
    go-musicfox
    pkgs-unstable.typora # 1.14.8 vs 1.13.6 on stable
  ];
}
