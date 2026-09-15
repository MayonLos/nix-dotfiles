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
      matlab
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

  # nvim decides a .m file's filetype by reading its first 100 lines
  # (runtime/lua/vim/filetype/detect.lua): a `%` comment makes it `matlab`, but
  # a `#` comment, `%!` or an Octave-only block terminator makes it `octave`.
  # nvim-treesitter registers the matlab parser for the `matlab` filetype only,
  # so the same grammar that highlights one script leaves the next one plain --
  # the difference being nothing but its comment style. Point `octave` at the
  # matlab parser so both land on it.
  #
  # Measured on the built binary, the shared parser is not a perfect fit: the
  # Octave-only keywords (`unwind_protect`, `endfunction`, `end_unwind_protect`)
  # come out as @function rather than @keyword, because tree-sitter-matlab has
  # no rule for them and falls back to a call expression. Everything else --
  # keywords, numbers, parameters, punctuation, folds -- is correct, and there
  # is no octave grammar to switch to. Accepted, not overlooked.
  extraConfigLua = ''
    vim.treesitter.language.register("matlab", "octave")
  '';
}
