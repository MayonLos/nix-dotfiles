_: {
  den.aspects.keys-mayon.homeManager = { pkgs, ... }: {
    home.packages = [ pkgs.keysMayon ];
  };
}
