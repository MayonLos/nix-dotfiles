{
  pkgs,
  home,
  nixos,
  appearance,
  ...
}:
{
  # Validates the generated 30px bar / Smart overlay Dock, source patch set,
  # native parser output and relocated tool bindings in the actual host config.
  interactive-session-config = import ./runtime-check.nix {
    inherit pkgs home;
    host = nixos;
    palette = appearance;
  };
}
