args@{
  pkgs,
  home,
  appearance,
  ...
}:
{
  visual-apps-config = import ../../../tests/composition/visual-apps.nix args;
  rime-technical-runtime = import ./rime-checks.nix {
    inherit pkgs home;
    palette = appearance;
  };
}
