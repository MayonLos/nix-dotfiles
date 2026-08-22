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

  keymaps = [
    {
      mode = "n";
      key = "<leader>ps";
      action.__raw = ''function() require("persistence").load() end'';
      options.desc = "Restore session for this directory";
    }
    {
      mode = "n";
      key = "<leader>pl";
      action.__raw = ''function() require("persistence").load({ last = true }) end'';
      options.desc = "Restore last session";
    }
    {
      mode = "n";
      key = "<leader>pd";
      action.__raw = ''function() require("persistence").stop() end'';
      options.desc = "Do not save this session";
    }
  ];
}
