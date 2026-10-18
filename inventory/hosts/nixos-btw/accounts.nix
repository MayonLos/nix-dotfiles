_: {
  den.aspects."mayon@nixos-btw" = {
    user = { pkgs, ... }: {
      isNormalUser = true;
      home = "/home/mayon";
      extraGroups = [
        "wheel"
        "networkmanager"
        "gamemode"
        "input"
        "dialout"
      ];
      shell = pkgs.zsh;
      packages = [ pkgs.tree ];
    };
    homeManager.home = {
      username = "mayon";
      homeDirectory = "/home/mayon";
      stateVersion = "25.11";
    };
  };
}
