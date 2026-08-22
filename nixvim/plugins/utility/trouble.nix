{
  # A navigable list for the things that are currently lists of locations:
  # diagnostics, LSP references, the quickfix stack. bqf (plugins/utility/bqf)
  # improves the quickfix window itself; this is the layer above it, where you
  # decide which list to look at.
  plugins.trouble = {
    enable = true;

    lazyLoad = {
      enable = true;
      settings.cmd = "Trouble";
    };

    settings = {
      focus = true;
      # Preview the entry under the cursor in the real buffer rather than a
      # scratch one, so LSP and treesitter highlighting are already there.
      preview = {
        type = "main";
        scratch = false;
      };
    };
  };

  keymaps = [
    {
      mode = "n";
      key = "<leader>xx";
      action = "<cmd>Trouble diagnostics toggle<cr>";
      options.desc = "Diagnostics (project)";
    }
    {
      mode = "n";
      key = "<leader>xX";
      action = "<cmd>Trouble diagnostics toggle filter.buf=0<cr>";
      options.desc = "Diagnostics (buffer)";
    }
    {
      mode = "n";
      key = "<leader>xs";
      action = "<cmd>Trouble symbols toggle<cr>";
      options.desc = "Symbol outline";
    }
    {
      mode = "n";
      key = "<leader>xl";
      action = "<cmd>Trouble lsp toggle win.position=right<cr>";
      options.desc = "LSP definitions / references";
    }
    {
      mode = "n";
      key = "<leader>xq";
      action = "<cmd>Trouble qflist toggle<cr>";
      options.desc = "Quickfix list";
    }
    {
      # todo-comments is already installed; this is its list view.
      mode = "n";
      key = "<leader>xt";
      action = "<cmd>Trouble todo toggle<cr>";
      options.desc = "TODO / FIXME";
    }
  ];
}
