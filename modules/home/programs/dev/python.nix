{ pkgs, ... }:
{
  # Bare interpreter only: project dependencies go through uv + direnv,
  # never into this global environment.
  home.packages = with pkgs; [
    # debugpy has to be *importable by this interpreter* — both dape (Emacs)
    # and nvim-dap launch the adapter as `python -m debugpy`. A loose
    # python3Packages.debugpy in the profile is not on this python's sys.path
    # and the adapter simply fails to start.
    (python3.withPackages (ps: [
      ps.debugpy
      ps.ipython
    ]))
    uv
    # ruff (linter + formatter) lives in toolchain.nix.
  ];
}
