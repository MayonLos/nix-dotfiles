{ pkgs, ... }:

let
  inherit ((import ../../lib/toolchains.nix { inherit pkgs; })) python;
in

{
  # Keep the native interpreter available in the shell; project dependencies
  # and version-specific environments go through uv + direnv.
  home.packages = with pkgs; [
    python
    uv
    # ruff (linter + formatter) lives in the selected language aspect.
  ];
}
