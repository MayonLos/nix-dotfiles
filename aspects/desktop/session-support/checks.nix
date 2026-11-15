args@{
  pkgs,
  home,
  appearance,
  ...
}:
{
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
    inherit pkgs home;
    palette = appearance;
  };
  rime-technical-runtime = import ./rime-checks.nix {
    inherit pkgs home;
    palette = appearance;
  };
}
