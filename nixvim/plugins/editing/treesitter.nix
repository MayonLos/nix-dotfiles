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
    folding.enable = true;

    nixvimInjections = true;
  };
}
