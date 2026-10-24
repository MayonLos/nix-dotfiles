{
  pkgs,
  home,
  appearance,
  ...
}:
{
  rime-technical-runtime = import ./rime-checks.nix {
    inherit pkgs home;
    palette = appearance;
  };
}
