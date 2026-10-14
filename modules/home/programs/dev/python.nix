{ pkgs, ... }:

let
  inherit ((import ../../../../lib/toolchains.nix { inherit pkgs; })) python;
in

{
  # IPython uses the shared interpreter; project dependencies go through
  # uv + direnv rather than this global environment.
  home.packages = with pkgs; [
    (python.withPackages (ps: [ ps.ipython ]))
    uv
    # ruff (linter + formatter) lives in toolchain.nix.
  ];
}
