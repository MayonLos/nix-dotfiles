{
  # Sessions keyed by directory, so reopening a project restores the buffers,
  # window layout and folds it had. Nothing here saves automatically on every
  # write — persistence hooks VimLeavePre, which is the only moment the state
  # is actually final.
  plugins.persistence = {
    enable = true;

    lazyLoad = {
      enable = true;
      settings.event = [ "BufReadPre" ];
    };

    settings = {
      # Without `folds` a restored session reopens every fold, which loses the
      # shape of a file you had carefully collapsed.
      options = [
        "buffers"
        "curdir"
        "tabpages"
        "winsize"
        "folds"
      ];
    };
  };

  # Each callback triggers the load itself. The plugin is lazy on BufReadPre,
  # and restoring a session is the one thing you do *before* any buffer is read
  # -- on a bare `nvim` these three died with "module 'persistence' not found".
  #
  # Declaring the same three lhs in `lazyLoad.settings.keys` does NOT fix it:
  # nixvim's own `keymaps` are applied after lz-n registers its stubs and
  # overwrite them, so the stub never fires. Measured in a real UI: pressing
  # <leader>pd on a bare nvim still left package.loaded["persistence"] nil.
  # `trigger_load` is the pattern used for fzf-lua in utility/open-url.nix and
  # navigation/fzf.nix, and it is independent of who owns the mapping.
  keymaps = [
    {
      mode = "n";
      key = "<leader>ps";
      action.__raw = ''
        function()
          require("lz.n").trigger_load("persistence.nvim")
          require("persistence").load()
        end
      '';
      options.desc = "Restore session for this directory";
    }
    {
      mode = "n";
      key = "<leader>pl";
      action.__raw = ''
        function()
          require("lz.n").trigger_load("persistence.nvim")
          require("persistence").load({ last = true })
        end
      '';
      options.desc = "Restore last session";
    }
    {
      mode = "n";
      key = "<leader>pd";
      action.__raw = ''
        function()
          require("lz.n").trigger_load("persistence.nvim")
          require("persistence").stop()
        end
      '';
      options.desc = "Do not save this session";
    }
  ];
}
