{ pkgs, ... }:
{
  # Bare interpreter only: project dependencies go through uv + direnv,
  # never into this global environment.
  home.packages = with pkgs; [
    python3
    uv
    ruff
    python3Packages.ipython
  ];
}
