_: {
  plugins.nvim-ufo = {
    enable = true;
    # The nixvim module selects pkgs.vimPlugins.nvim-ufo, whose nixpkgs
    # dependencies include promise-async; no second manual package is needed.
    setupLspCapabilities = false;
    lazyLoad = {
      enable = true;
      settings = {
        event = [
          "BufReadPost"
          "BufNewFile"
        ];
        cmd = [
          "UfoEnable"
          "UfoDisable"
          "UfoInspect"
          "UfoAttach"
          "UfoDetach"
        ];
        keys = [
          "zR"
          "zM"
          "zK"
        ];
      };
    };
    # Keep the existing parser-based folding without depending on each LSP's
    # folding support; indent covers buffers without a Treesitter fold query.
    settings.provider_selector = ''
      function()
        return { "treesitter", "indent" }
      end
    '';
  };

  opts = {
    foldmethod = "manual";
    foldenable = true;
    foldlevelstart = 99; # Match foldlevel = 99: opening a file keeps its folds open.
    # Snacks already draws the fold group on the right of the statuscolumn.
    foldcolumn = "0";
  };

  keymaps = [
    {
      mode = "n";
      key = "zR";
      action.__raw = ''function() require("ufo").openAllFolds() end'';
      options.desc = "Open all folds";
    }
    {
      mode = "n";
      key = "zM";
      action.__raw = ''function() require("ufo").closeAllFolds() end'';
      options.desc = "Close all folds";
    }
    {
      mode = "n";
      key = "zK";
      action.__raw = ''function() require("ufo").peekFoldedLinesUnderCursor() end'';
      options.desc = "Preview folded lines";
    }
  ];
}
