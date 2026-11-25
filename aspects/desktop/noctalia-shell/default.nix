{ den, ... }:
{
  imports = [ ../../appearance/appearance ];
  den.aspects.noctalia-shell =
    { user, ... }:
    {
      homeManager = {
        imports = [
          (import ./noctalia.nix { palette = user.appearance; })
          ./services.nix
        ];
      };
    };
}
