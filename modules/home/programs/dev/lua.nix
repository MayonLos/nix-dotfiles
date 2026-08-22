{ lib, pkgs, ... }:
{
  home.packages = with pkgs; [
    lua5_4
    # luajit also ships bin/lua; lowPrio keeps lua5_4 as the default `lua`
    (lib.lowPrio luajit)
    lua54Packages.luarocks
    # lua-language-server, luacheck and stylua live in toolchain.nix.
  ];

  # `luarocks install --local` drops executables here
  home.sessionPath = [ "$HOME/.luarocks/bin" ];
}
