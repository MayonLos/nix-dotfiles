{ host }: {
  programs.nh = {
    enable = true;
    flake = host.flakePath;
    clean = {
      enable = true;
      extraArgs = "--keep 5 --keep-since 14d";
    };
  };
}
