{ pkgs, ... }: {
  home.packages = with pkgs; [
    bat
    eza
    ripgrep
    duf
    nix-output-monitor
    fd
    jq
    hexyl
    dust
    tealdeer
    sops
    p7zip
    libqalculate
  ];
}
