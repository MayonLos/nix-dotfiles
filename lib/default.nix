{ pkgs, lib }:
{
  obsidian = import ./obsidian-helpers.nix { inherit pkgs lib; };
  keybinds = import ./keybind-helpers.nix { inherit lib; };
}
