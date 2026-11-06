_: {
  den.schema.user.imports = [ ./contract.nix ];

  den.aspects.game-tunnel =
    { user, ... }:
    assert user.gameTunnel != null;
    {
      homeManager =
        { pkgs, lib, ... }:
        import ./home.nix {
          inherit pkgs lib;
          tunnel = user.gameTunnel;
        };
    };
}
