{ pkgs, ... }:
{
  # `opts` (vim.opt), not `globalOpts` (vim.opt_global). opt_global sets only
  # the *global default*, which window-local and buffer-local options copy at
  # creation time — and the startup window and buffer both exist before init.lua
  # runs. The result was that number, relativenumber, cursorline, list and
  # signcolumn never applied to the window you actually opened: `nvim file`
  # rendered with no line numbers at all. Verified against the pre-migration
  # build too, so this predates moving the config into nix-dotfiles.
  opts = {
    number = true;
    relativenumber = true;
    termguicolors = true;
    ignorecase = true;
    smartcase = true;
    expandtab = true;
    shiftwidth = 4;
    tabstop = 4;
    softtabstop = 4;
    smartindent = true;
    list = true;
    listchars.__raw = "{ tab = '» ', trail = '·', nbsp = '␣' }";
    undofile = true;
    swapfile = false;
    cursorline = true;
    scrolloff = 8;
    conceallevel = 2;
    laststatus = 3;
    showtabline = 2;
    winborder = "rounded";
    signcolumn = "yes";
    splitright = true;
    splitbelow = true;
    updatetime = 250;
    timeoutlen = 400;
    foldlevel = 99;
  };

  globals.mapleader = " ";

  extraConfigLua = ''
    vim.opt.fillchars:append({
      vert = " ",
      vertleft = " ",
      vertright = " ",
      verthoriz = " ",
    })
  '';

  clipboard = {
    register = "unnamedplus";
    providers.wl-copy.enable = pkgs.stdenv.hostPlatform.isLinux;
  };
}
