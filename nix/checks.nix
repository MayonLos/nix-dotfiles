{ inputs, ... }: {
  perSystem = { pkgs, ... }: {
    checks.system-boundaries = import ../tests/composition/system.nix { inherit inputs pkgs; };
  };
}
