{ withSystem, inputs, ... }:
let
  pkgs-unstable-for =
    system:
    import inputs.nixpkgs-unstable {
      inherit system;
      config.allowUnfree = true;
      overlays = [ inputs.claude-code.overlays.default ];
    };

  importDir =
    dir:
    builtins.concatLists (
      builtins.attrValues (
        builtins.mapAttrs (
          name: type:
          if (type == "regular" || type == "symlink") && builtins.match ".*\\.nix" name != null then
            [ (dir + "/${name}") ]
          else if type == "directory" then
            importDir (dir + "/${name}")
          else
            [ ]
        ) (builtins.readDir dir)
      )
    );
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
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = {
              inherit inputs;
              pkgs-unstable = pkgs-unstable-for "x86_64-linux";
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
