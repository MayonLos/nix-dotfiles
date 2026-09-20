{ pkgs, config, ... }:
{
  home.packages = [
    # Not callPackage: pkgs/matlab.nix needs the whole package set to build its
    # FHS target list, and the user's real home directory to find the install
    # tree. See the header comment there for why MATLAB itself cannot be a
    # derivation -- octave.nix covers the .m work that does not need it.
    (import ../../../../pkgs/matlab.nix {
      inherit pkgs;
      inherit (config.home) homeDirectory;
    })
  ];
}
