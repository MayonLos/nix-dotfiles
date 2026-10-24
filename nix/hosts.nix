{
  den,
  inputs,
  lib,
  withSystem,
  ...
}:
{
  den.schema.host = {
    imports = [
      ({ config, ... }: {
        options.homeManagerArgs = lib.mkOption {
          type = lib.types.attrs;
          description = "Global Home Manager special arguments for this host.";
        };
        config.homeManagerArgs = lib.mkDefault {
          inherit inputs;
          hostFacts = config.facts;
        };
        config.instantiate = lib.mkDefault (
          args:
          withSystem config.system (
            { pkgs, ... }:
            inputs.nixpkgs.lib.nixosSystem (
              args
              // {
                inherit pkgs;
                specialArgs = (args.specialArgs or { }) // {
                  inherit inputs;
                  hostFacts = config.facts;
                };
              }
            )
          )
        );
      })
    ];
    includes = [ den.aspects.host-pipeline ];
  };
  den.aspects.host-pipeline = { host, ... }: {
    nixos.home-manager = {
      useGlobalPkgs = lib.mkDefault true;
      useUserPackages = lib.mkDefault true;
      backupFileExtension = lib.mkDefault "backup";
      # HM adds nixosConfig at ordinary priority to this shallow attrs option.
      # Apply defaults at the host schema boundary, then hand the full attrset
      # to HM at ordinary priority so upstream's key does not discard it.
      extraSpecialArgs = host.homeManagerArgs;
    };
  };
}
