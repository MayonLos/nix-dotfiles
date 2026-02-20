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

    quickshell = {
      url = "github:quickshell-mirror/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
  inputs@
    {
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      MyNixvim,
      niri,
      quickshell,
      ...
    }:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations.nixos-btw = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        inherit system;
        modules = [
          niri.nixosModules.niri
          ./configuration.nix

          {
            nixpkgs = {
              config.allowUnfree = true;
              overlays = [ niri.overlays.niri ];
            };
          }

          home-manager.nixosModules.home-manager
          {
            home-manager = {
              useGlobalPkgs = true;
              useUserPackages = true;
              extraSpecialArgs = {
                inherit
                  nixpkgs-unstable
                  MyNixvim
                  quickshell
                ;
              };
              users.mayon = import ./host/home.nix;
              backupFileExtension = "backup";
            };
          }
        ];
      };
    };
}
