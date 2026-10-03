{ lib, pkgs, ... }:

let
  toolchains = import ../../../../lib/toolchains.nix { inherit pkgs; };
in

{
  home.packages = with pkgs; [
    toolchains.lua
    # luajit also ships bin/lua; lowPrio keeps lua5_4 as the default `lua`
    (lib.lowPrio luajit)
    toolchains.luaPackages.luarocks
    # lua-language-server, luacheck and stylua live in toolchain.nix.
  ];

  # `luarocks install --local` drops executables here
  home.sessionPath = [ "$HOME/.luarocks/bin" ];
}
