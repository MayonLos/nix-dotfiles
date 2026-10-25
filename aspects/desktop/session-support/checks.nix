args@{
  pkgs,
  home,
  appearance,
  ...
}:
{
  visual-apps-config = import ../../../tests/composition/visual-apps.nix args;
  gtk-qt-theme = import ./theme-check.nix {
    inherit pkgs home;
    palette = appearance;
  };
  rime-technical-runtime = import ./rime-checks.nix {
    inherit pkgs home;
    palette = appearance;
  };
}
