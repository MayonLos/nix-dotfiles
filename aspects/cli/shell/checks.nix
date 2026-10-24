{
  pkgs,
  home,
  nixos,
  appearance,
  ...
}:
{
  command-line-runtime = import ./runtime-check.nix {
    inherit pkgs home;
    systemPath = nixos.system.path;
    palette = appearance;
  };
}
