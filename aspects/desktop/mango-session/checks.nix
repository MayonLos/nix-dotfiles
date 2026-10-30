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

  # Validates the generated 30px bar / Smart overlay Dock, source patch set,
  # native parser output, Launchpad model/manifest and tool bindings in the actual host config.
  interactive-session-config = import ./runtime-check.nix {
    inherit pkgs home;
    host = nixos;
    palette = appearance;
  };
}
