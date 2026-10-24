{
  pkgs,
  home,
  nixos,
  ...
}:
let
  checks = import ./runtime-checks.nix {
    inherit pkgs;
    profile = home.home.path;
    rules = nixos.environment.etc."udev/rules.d".source;
  };
in
{
  embedded-udev = checks.udev;
  embedded-tools = checks.tools;
}
