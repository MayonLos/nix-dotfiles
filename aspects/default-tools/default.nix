_: {
  den.schema.user.imports = [ ./contract.nix ];

  den.aspects.default-tools = { user, ... }: {
    homeManager = import ./consumer.nix { tools = user.defaultTools; };
  };
}
