args@{
  pkgs,
  home,
  appearance,
  ...
}:
let
  templateRuntime = import ./template-runtime-check.nix {
    inherit pkgs home;
    palette = appearance;
  };
in
{
  noctalia-template-runtime = templateRuntime;
  visual-apps-config = import ../../../tests/composition/visual-apps.nix args;
  gtk-qt-theme = import ./theme-check.nix {
    inherit pkgs home templateRuntime;
    palette = appearance;
  };
  rime-technical-runtime = import ./rime-checks.nix {
    inherit pkgs home;
    palette = appearance;
  };
}
