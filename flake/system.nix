{ withSystem, inputs, ... }:
let
  inherit (import ../lib) importDir;

  system = "x86_64-linux";
in
{
  flake.nixosConfigurations.nixos-btw = withSystem system (
    { pkgs, pkgs-unstable, ... }:
    let
      extraArgs = { inherit inputs pkgs-unstable; };
    in
    inputs.nixpkgs.lib.nixosSystem {
      inherit pkgs;
      specialArgs = extraArgs;
      modules = [
        ../hosts/nixos-btw
        inputs.sops-nix.nixosModules.sops
        inputs.home-manager.nixosModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            backupFileExtension = "backup";
            extraSpecialArgs = extraArgs;
            users.mayon = {
              imports = importDir ../modules/home;
            };
          };
        }
      ];
    }
  );
}
