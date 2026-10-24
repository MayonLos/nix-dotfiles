{ pkgs, home, ... }: {
  rime-technical-runtime = import ./rime-checks.nix { inherit pkgs home; };
}
