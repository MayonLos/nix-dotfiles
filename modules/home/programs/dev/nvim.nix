{ pkgs, ... }:
let
  editor = import ../../../../pkgs/neovim { inherit pkgs; };
in
{
  home.packages = [ editor.normal ];
  # Same source as the wrapper. The init resolves this symlink to its Lua tree;
  # linking only init avoids duplicating queries on the XDG runtimepath.
  xdg.configFile."nvim/init.lua".source = "${editor.configDir}/init.lua";
}
