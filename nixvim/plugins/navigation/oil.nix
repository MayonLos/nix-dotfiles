{
  plugins.oil = {
    enable = true;

    lazyLoad.settings.cmd = "Oil";

    settings = {
      default_file_explorer = true;
      columns = [
        "icon"
        "permissions"
        "size"
        "mtime"
      ];

      buf_options = {
        buflisted = false;
        bufhidden = "hide";
      };

      win_options = {
        wrap = false;
        signcolumn = "no";
        cursorcolumn = false;
        foldcolumn = "0";
        spell = false;
        list = false;
        conceallevel = 3;
        concealcursor = "nvic";
      };

      delete_to_trash = true;
      skip_confirm_for_simple_edits = true;
      prompt_save_on_select_new_entry = false;
      cleanup_delay_ms = 2000;
      constrain_cursor = "editable";
      watch_for_changes = true;

      lsp_file_methods = {
        enabled = true;
        timeout_ms = 1000;
        autosave_changes = "unmodified";
      };

      keymaps = {
        "q" = {
          __unkeyed-1 = "actions.close";
          mode = "n";
        };
        "<Esc>" = {
          __unkeyed-1 = "actions.close";
          mode = "n";
        };
      };
      use_default_keymaps = true;

      view_options = {
        show_hidden = false;
        is_hidden_file.__raw = ''
          function(name, _)
            return vim.startswith(name, ".")
          end
        '';
        is_always_hidden.__raw = ''
          function(name, _)
            return name == ".." or name == ".git"
          end
        '';
        natural_order = true;
        case_insensitive = false;
        sort = [
          [
            "type"
            "asc"
          ]
          [
            "name"
            "asc"
          ]
        ];
      };

      float = {
        padding = 2;
        max_width = 90;
        max_height = 0;
        border = "rounded";
        win_options = {
          winblend = 0;
          winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder,FloatTitle:FloatTitle";
        };
        get_win_title.__raw = ''
          function(winid)
            local bufnr = vim.api.nvim_win_get_buf(winid)
            local dir = require("oil").get_current_dir(bufnr)
            if not dir then return "" end
            return "  " .. vim.fn.fnamemodify(dir, ":~") .. " "
          end
        '';
      };

      preview_win = {
        update_on_cursor_moved = true;
        preview_method = "fast_scratch";
      };

      confirmation = {
        border = "rounded";
        win_options.winblend = 0;
      };

      progress = {
        border = "rounded";
        minimized_border = "none";
        win_options.winblend = 0;
      };
    };
  };

  keymaps = [
    {
      mode = "n";
      key = "-";
      action = "<cmd>Oil<cr>";
      options.desc = "Oil: open parent directory";
    }
    {
      mode = "n";
      key = "<leader>oo";
      action = "<cmd>Oil<cr>";
      options.desc = "Oil: open parent directory";
    }
    {
      mode = "n";
      key = "<leader>oO";
      action = "<cmd>Oil --float<cr>";
      options.desc = "Oil: open in float";
    }
  ];
}
