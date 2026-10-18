_: {
  den.aspects.communication = _: {
    homeManager = { pkgs, ... }: {
      imports = [
        ./im.nix
        ./thunderbird.nix
      ];
      home.packages = [ pkgs.discord ];
    };
  };
}
