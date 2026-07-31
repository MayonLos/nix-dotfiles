{ lib, pkgs, ... }:
{
  home.packages = with pkgs; [
    lua5_4
    # luajit also ships bin/lua; lowPrio keeps lua5_4 as the default `lua`
    (lib.lowPrio luajit)
    lua54Packages.luarocks
    lua54Packages.luacheck
    lua-language-server
    stylua
  ];

  # `luarocks install --local` drops executables here
  home.sessionPath = [ "$HOME/.luarocks/bin" ];
}
