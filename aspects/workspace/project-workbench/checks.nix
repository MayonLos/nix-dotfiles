{ pkgs, ... }:
{
  project-workbench = import ./runtime-check.nix { inherit pkgs; };
}
