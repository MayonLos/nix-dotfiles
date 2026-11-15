{
  pkgs,
  home,
  nixos,
  appearance,
  ...
}:
{
  noctalia-clash-status =
    (import ../../../packages/noctalia-clash-status { inherit pkgs; }).tests.status;

  mango-blur-sampling = import ./mango/blur-check.nix {
    inherit pkgs;
    mango = nixos.programs.mango.package;
  };

  noctalia-osd-pixels = import ./noctalia/r50-osd-check.nix {
    inherit pkgs;
    noctalia = home.programs.noctalia.package;
    palette = home.programs.noctalia.customPalettes.onedark;
  };

  # Validates mangobar, fuzzel, mako, swayosd, the dormant Noctalia bar,
  # the Smart Dock, source patches, parser output and tool bindings.
  interactive-session-config = import ./runtime-check.nix {
    inherit pkgs home;
    host = nixos;
    palette = appearance;
  };
}
