{ den, ... }:
{
  imports = [ ../../desktop/mango-session ];
  den.schema = {
    host.imports = [ ./contract.nix ];
    user.imports = [ ./contract.nix ];
  };

  den.aspects = {
    avatar =
      { host, user, ... }:
      {
        noctaliaIntegrations = [ { id = "avatar"; } ];
        homeManager = import ./home.nix { inherit host user; };
        provides.${host.name}.includes = [ den.aspects.avatar-host ];
      };
    avatar-host = { host, ... }: {
      nixos = import ./nixos.nix { inherit host; };
    };
  };
}
