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
    # The switch that keeps a rendered line rendered when the cursor lands on
    # it -- and it is a *window* option, not a plugin one, which is why no
    # amount of reading snacks' or render-markdown's config finds it.
    # snacks/image/inline.lua:45 returns early from its conceal pass when
    # `vim.wo.concealcursor` contains the current mode, so every image in the
    # cursor's line stays shown. Without it, walking down a document takes the
    # typeset formulae apart one line at a time.
    #
    # "nvic" is all four modes, insert included, because the point is to see
    # the document while writing it.
    #
    # This is the global default and markdown does NOT use it: render-markdown
    # sets `concealcursor` per window from its own
    # `win_options.concealcursor.rendered`, which is where the markdown value
    # actually lives (plugins/utility/render-markdown.nix). Changing this line
    # alone does nothing to a note.
    concealcursor = "nvic";
    laststatus = 3;
    showmode = false; # Heirline already shows the mode beside the filename.
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
