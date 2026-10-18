{ inputs, ... }:
{
  imports = [
    inputs.den.flakeModule
    inputs.home-manager.flakeModules.home-manager
    inputs.treefmt-nix.flakeModule
    ./checks.nix
    ./den.nix
    ./nixpkgs.nix
    ./dev.nix
    ./neovim.nix
    ../aspects
    ../bundles
    ../inventory/hosts/nixos-btw
  ];
}
