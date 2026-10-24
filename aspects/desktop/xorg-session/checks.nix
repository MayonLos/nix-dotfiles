{
  pkgs,
  home,
  nixos,
  appearance,
  ...
}:
{
  xorg-session-runtime = import ./runtime-check.nix {
    inherit pkgs home appearance;
    host = nixos;
  };
}
