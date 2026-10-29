_: {
  imports = [ ../../appearance/appearance ];
  den.aspects.clash-tui = { user, ... }: {
    homeManager = { pkgs, ... }: {
      home.packages = [
        (import ./package.nix {
          inherit pkgs;
          palette = user.appearance;
        })
      ];
    };
  };
  # Explicit local registration keeps the feature's verification hook nearby.
  perSystem = { pkgs, ... }: {
    checks = import ./checks.nix {
      inherit pkgs;
      appearance = import ../../appearance/appearance/onedark.nix;
    };
  };
}
