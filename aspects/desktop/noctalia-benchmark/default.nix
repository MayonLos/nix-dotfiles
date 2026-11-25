{ den, ... }:
{
  den.aspects.noctalia-benchmark = {
    homeManager = {
      imports = [ ./benchmark.nix ];
    };
  };
}
