{
  pkgs,
  pkgs-unstable,
  ...
}:

{
  home.packages = with pkgs; [
    qt6Packages.qt6ct
    pkgs-unstable.github-copilot-cli
    pkgs-unstable.claude-code
    # codex, chatgpt, dsh, opencode, zcode and the agent-side tooling come from
    # programs/dev/ai-agents.nix — packaged by the llm-agents.nix input.
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
    # Editing secrets/secrets.yaml is routine enough to want outside `nix develop`.
    sops
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
