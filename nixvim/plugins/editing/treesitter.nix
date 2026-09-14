{ pkgs, ... }:
{
  plugins.treesitter = {
    enable = true;

    grammarPackages = with pkgs.vimPlugins.nvim-treesitter.builtGrammars; [
      c
      cpp
      cuda
      python
      nix
      lua
      luadoc
      vim
      vimdoc
      html
      markdown
      markdown_inline
      bash
      java
      latex
      bibtex
      yaml
      json
      toml
      kdl
      gitcommit
      diff
      regex
      query
    ];

    highlight = {
      enable = true;
      disable = [ "latex" ];
    };
    indent.enable = true;
    # Kept on even though ufo computes its own treesitter ranges: foldexpr is
    # synchronous, ufo's provider is not. Without it a buffer has no folds at
    # all for the ~2s until ufo attaches, and `zc` right after opening a file
    # fails with E490. ufo takes over from here -- its README: "foldmethod
    # option will finally become manual if ufo is working".
    folding.enable = true;

    nixvimInjections = true;
  };
}
