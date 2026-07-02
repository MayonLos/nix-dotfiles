_: {
  programs.nh = {
    enable = true;
    flake = "/home/mayon/nix-dotfiles";
    clean = {
      enable = true;
      extraArgs = "--keep 5 --keep-since 14d";
    };
  };
}
