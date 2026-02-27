{
  description = "NixOS from Scratch";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.11";
    
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    MyNixvim = {
      url = "github:MayonLos/nixvim";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    niri.url = "github:sodiboo/niri-flake";
  };

  outputs = inputs@{ nixpkgs, ... }:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.nixos-btw = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        inherit system;
        modules = [
          inputs.niri.nixosModules.niri
          ./configuration.nix

          {
            nixpkgs = {
              config.allowUnfree = true;
            };
          }

          inputs.home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = { inherit inputs; };
              users.mayon = import ./host/home.nix;
              backupFileExtension = "backup";
            };
          }
        ];
      };
    };
}
