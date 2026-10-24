{ inputs, ... }:
{
  imports = [
    inputs.den.flakeModule
    inputs.home-manager.flakeModules.home-manager
    inputs.treefmt-nix.flakeModule
    ./checks.nix
    ./den.nix
    ./pkgs.nix
    ./hosts.nix
    ./dev.nix
    ./outputs.nix
    ../aspects
    ../bundles
    ../inventory/hosts/nixos-btw
  ];
}
