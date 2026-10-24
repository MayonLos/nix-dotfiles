{
  pkgs,
  home,
  nixos,
  ...
}:
{
  xorg-session-runtime = import ./runtime-check.nix {
    inherit pkgs home;
    host = nixos;
  };
}
