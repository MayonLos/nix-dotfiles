_: {
  den.aspects.workspace-task.homeManager =
    { pkgs, ... }:
    {
      home.packages = [ (import ./package.nix { inherit pkgs; }) ];
    };
}
