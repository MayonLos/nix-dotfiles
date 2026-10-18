{ inputs, ... }:
{
  imports = [
    inputs.den.flakeModule
    inputs.home-manager.flakeModules.home-manager
    inputs.treefmt-nix.flakeModule
    ./den.nix
    ./nixpkgs.nix
    ../flake/dev.nix
    ../flake/neovim.nix
    ../inventory/hosts/nixos-btw
  ];
}
