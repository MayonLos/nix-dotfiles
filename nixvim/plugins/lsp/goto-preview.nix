{
  plugins.goto-preview = {
    enable = true;
    settings = {
      default_mappings = false;
      height = 30;
      post_open_hook.__raw = ''
        function(_, win)
          local function close_window()
            vim.api.nvim_win_close(win, true)
          end
          vim.keymap.set("n", "<Esc>", close_window, { buffer = true })
          vim.keymap.set("n", "q", close_window, { buffer = true })
        end
      '';
    };
  };

  keymaps = [
    {
      mode = "n";
      key = "gpd";
      action.__raw = "function() require('goto-preview').goto_preview_definition() end";
      options.desc = "Preview definition";
    }
    {
      mode = "n";
      key = "gpi";
      action.__raw = "function() require('goto-preview').goto_preview_implementation() end";
      options.desc = "Preview implementation";
    }
    {
      mode = "n";
      key = "gpt";
      action.__raw = "function() require('goto-preview').goto_preview_type_definition() end";
      options.desc = "Preview type definition";
    }
    {
      mode = "n";
      key = "gpr";
      action.__raw = "function() require('goto-preview').goto_preview_references() end";
      options.desc = "Preview references";
    }
    {
      mode = "n";
      key = "gP";
      action.__raw = "function() require('goto-preview').close_all_win() end";
      options.desc = "Close all preview windows";
    }
  ];
}
