_: {
  den.aspects.science = {
    homeManager = { pkgs, ... }: {
      home.packages = [
        (import ./octave.nix { inherit pkgs; })
      ];
    };
  };
}
