{ withSystem, inputs, ... }:
let
  importDir = import ../lib/import-dir.nix;

  pkgs-unstable-for =
    system:
    import inputs.nixpkgs-unstable {
      inherit system;
      config.allowUnfree = true;
      overlays = [ inputs.claude-code.overlays.default ];
    };
in
{
  flake.nixosConfigurations.nixos-btw = withSystem "x86_64-linux" (
    { pkgs, ... }:
    let
      pkgs-unstable = pkgs-unstable-for "x86_64-linux";
    in
    inputs.nixpkgs.lib.nixosSystem {
      inherit pkgs;
      specialArgs = {
        inherit inputs pkgs-unstable;
      };
      modules = [
        ../hosts/nixos-btw
        inputs.sops-nix.nixosModules.sops
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "backup";
            extraSpecialArgs = {
              inherit inputs pkgs-unstable;
            };
            users.mayon = {
              imports = importDir ../modules/home;
            };
          };
        }
      ];
    }
  );
}
