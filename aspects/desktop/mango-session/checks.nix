{
  pkgs,
  home,
  nixos,
  appearance,
  ...
}:
{
  interactive-session-config = import ./runtime-check.nix {
    inherit pkgs home;
    host = nixos;
    palette = appearance;
  };
  mango-focused-shadow = import ./focus-check.nix {
    inherit pkgs home;
    host = nixos;
    palette = appearance;
  };
}
