{ pkgs, ... }: {
  home.packages = with pkgs; [
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

  programs.bat = {
    enable = true;
    config = {
      theme = "base16";
      style = "numbers,changes,header";
    };
  };
}
