{ inputs, withSystem, ... }:
let
  inherit (import ../../../lib) importDir;
in
{
  den.hosts.x86_64-linux.nixos-btw = {
    users.mayon = { };
    # Den owns output generation. Preserve the existing package instances and
    # explicit special arguments at the OS instantiation boundary.
    instantiate =
      args:
      withSystem "x86_64-linux" (
        { pkgs, pkgs-unstable, ... }:
        inputs.nixpkgs.lib.nixosSystem (
          args
          // {
            inherit pkgs;
            specialArgs = (args.specialArgs or { }) // {
              inherit inputs pkgs-unstable;
            };
          }
        )
      );
  };
  den.aspects.nixos-btw.nixos = {
    imports = [
      ../../../hosts/nixos-btw
      inputs.sops-nix.nixosModules.sops
    ];
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = "backup";
      extraSpecialArgs = {
        inherit inputs;
      }
      // withSystem "x86_64-linux" ({ pkgs-unstable, ... }: { inherit pkgs-unstable; });
    };
  };
  den.aspects."mayon@nixos-btw".homeManager.imports = importDir ../../../modules/home;
}
