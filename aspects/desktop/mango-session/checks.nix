{
  pkgs,
  home,
  nixos,
  appearance,
  ...
}:
{
  mango-blur-sampling = import ./mango/blur-check.nix {
    inherit pkgs;
    mango = nixos.programs.mango.package;
  };

  # Validates the generated 30px bar / Smart overlay Dock, source patch set,
  # native parser output, Launchpad model/manifest and tool bindings in the actual host config.
  interactive-session-config = import ./runtime-check.nix {
    inherit pkgs home;
    host = nixos;
    palette = appearance;
  };
}
