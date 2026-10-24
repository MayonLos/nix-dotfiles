_: {
  imports = [ ../../appearance/appearance ];
  den.aspects.herdr = { user, ... }: {
    homeManager = import ./home.nix { palette = user.appearance; };
  };
}
