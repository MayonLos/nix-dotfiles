_: {
  imports = [ ../../appearance/appearance ];
  den.aspects.terminal = { user, ... }: {
    homeManager = import ./kitty.nix { palette = user.appearance; };
  };
}
