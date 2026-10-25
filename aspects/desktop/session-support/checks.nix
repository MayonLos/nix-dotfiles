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
  office-fonts = import ./font-check.nix {
    inherit pkgs;
    inherit (args) nixos;
  };
  application-portals-theme = import ./portal-check.nix {
    inherit pkgs home;
    inherit (args) nixos;
    inherit appearance;
  };
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
