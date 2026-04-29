{ withSystem, inputs, ... }:
let
  pkgs-unstable-for = system:
    import inputs.nixpkgs-unstable {
      inherit system;
      config.allowUnfree = true;
      overlays = [ inputs.claude-code.overlays.default ];
    };
in
{
  flake.nixosConfigurations.nixos-btw = withSystem "x86_64-linux" (
    { pkgs, ... }:
    inputs.nixpkgs.lib.nixosSystem {
      inherit pkgs;
      specialArgs = {
        inherit inputs;
        pkgs-unstable = pkgs-unstable-for "x86_64-linux";
      };
      modules = [
        inputs.niri.nixosModules.niri
        ../hosts/nixos-btw
        inputs.home-manager.nixosModules.home-manager
        {
          nixpkgs.config.allowUnfree = true;
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = {
              inherit inputs;
              pkgs-unstable = pkgs-unstable-for "x86_64-linux";
            };
            users.mayon = import ../modules/home/users/mayon;
            backupFileExtension = "backup";
          };
        }
      ];
    }
  );
}
