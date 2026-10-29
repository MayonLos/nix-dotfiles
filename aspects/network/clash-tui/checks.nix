{ pkgs, appearance, ... }:
{
  # buildRustPackage runs cargo test and clippy as well as the release build.
  clash-tui = import ./package.nix {
    inherit pkgs;
    palette = appearance;
  };
}
