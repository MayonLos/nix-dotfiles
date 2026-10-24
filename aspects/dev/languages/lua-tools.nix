{ pkgs, ... }:

let
  toolchains = import ./toolchains.nix { inherit pkgs; };
in

{
  home.packages = [
    toolchains.lua
    # Project-specific Lua versions and packages belong in the project flake.
    # lua-language-server, luacheck and stylua live in the selected language aspect.
  ];
}
