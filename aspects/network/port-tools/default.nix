_: {
  den.aspects.port-tools.homeManager = { pkgs, ... }: {
    home.packages = [ pkgs.mayonTui.ports ];
  };
}
