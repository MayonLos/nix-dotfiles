{
  plugins.goto-preview = {
    enable = true;

    # Lazy-load on its own maps: nothing else calls into goto-preview, so the
    # plugin does not need to be in the startup set. The maps live here rather
    # than in the top-level keymaps list so lz.n can load before firing.
    lazyLoad.settings.keys = [
      {
        __unkeyed-1 = "gpd";
        __unkeyed-2.__raw = "function() require('goto-preview').goto_preview_definition() end";
        desc = "Preview definition";
      }
      {
        __unkeyed-1 = "gpi";
        __unkeyed-2.__raw = "function() require('goto-preview').goto_preview_implementation() end";
        desc = "Preview implementation";
      }
      {
        __unkeyed-1 = "gpt";
        __unkeyed-2.__raw = "function() require('goto-preview').goto_preview_type_definition() end";
        desc = "Preview type definition";
      }
      {
        __unkeyed-1 = "gpr";
        __unkeyed-2.__raw = "function() require('goto-preview').goto_preview_references() end";
        desc = "Preview references";
      }
      {
        __unkeyed-1 = "gP";
        __unkeyed-2.__raw = "function() require('goto-preview').close_all_win() end";
        desc = "Close all preview windows";
      }
    ];

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
}
