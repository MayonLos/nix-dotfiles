_: {
  plugins.vim-matchup = {
    enable = true;

    lazyLoad.settings.event = [
      "BufReadPost"
      "BufNewFile"
    ];
    settings = {
      matchparen_offscreen.method = "popup";
      surround_enabled = 1;
      transmute_enabled = 1;
    };
  };

  # There is deliberately no `plugins.treesitter.settings.matchup.enable` here.
  # It went into the same ignored table as the settings that
  # editing/treesitter-textobjects.nix had to stop using, and
  # `require("nvim-treesitter.matchup")` does not exist in the archived
  # main-branch nvim-treesitter this flake pins -- so the treesitter-aware
  # matching it was written for never happened. vim-matchup itself works, in
  # regex mode (`g:loaded_matchup = 1`, its matchparen autocmd is registered).
  # The `mkForce` also suppressed any default-vs-explicit signal, which is what
  # kept it looking effective.
}
