{
  ...
}:

{
  imports = [
    ../home/dwm/suckless.nix
    ../home/niri/default.nix
    ../home/service/default.nix
    ../home/program/default.nix
    ../home/shell/default.nix

    ./home/base.nix
    ./home/input-method.nix
    ./home/ui.nix
    ./home/xdg.nix

    ./packages.nix
    ./scripts/X11/default.nix
  ];
}
