_: {
  den.aspects.mayon-tools.homeManager = { pkgs, ... }: {
    home.packages = [ pkgs.mayonTui.tools ];
  };
}
