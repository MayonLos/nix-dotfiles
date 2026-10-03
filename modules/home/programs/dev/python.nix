{ pkgs, ... }:

let
  inherit ((import ../../../../lib/toolchains.nix { inherit pkgs; })) python;
in

{
  # Bare interpreter only: project dependencies go through uv + direnv,
  # never into this global environment. toolchain.nix's Python packages and
  # the `python3` nvim-dap starts resolve to this same interpreter.
  home.packages = with pkgs; [
    # debugpy has to be *importable by this interpreter* — nvim-dap launches
    # the adapter as `python -m debugpy`. A loose package in the profile is not
    # on this python's sys.path and the adapter simply fails to start.
    (python.withPackages (ps: [
      ps.debugpy
      ps.ipython
    ]))
    uv
    # ruff (linter + formatter) lives in toolchain.nix.
  ];
}
