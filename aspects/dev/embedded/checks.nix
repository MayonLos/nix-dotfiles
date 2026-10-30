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
  serial-mayon =
    assert builtins.elem pkgs.mayonTui.tools.outPath (
      map (package: package.outPath) home.home.packages
    );
    pkgs.mayonTui.tools;
}
