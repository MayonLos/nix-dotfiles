_: {
  den.schema.host.imports = [ ./contract.nix ];
  den.aspects = {
    system-maintenance = { host, ... }: {
      nixos.imports = [
        ./nix.nix
        ./locale.nix
        ./tools.nix
        (import ./nh.nix { inherit host; })
      ];
    };
  };
}
