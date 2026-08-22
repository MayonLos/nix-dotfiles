{
  plugins.fzf-lua = {
    enable = true;
    lazyLoad = {
      enable = true;
      settings = {
        cmd = [ "FzfLua" ];
        keys = [
          {
            __unkeyed-1 = "<leader>ff";
            __unkeyed-2 = "<cmd>FzfLua files<cr>";
            desc = "Find Files";
          }
          {
            __unkeyed-1 = "<leader>fg";
            __unkeyed-2 = "<cmd>FzfLua live_grep<cr>";
            desc = "Live Grep";
          }
          {
            __unkeyed-1 = "<leader>fb";
            __unkeyed-2 = "<cmd>FzfLua buffers<cr>";
            desc = "Buffers";
          }
          {
            __unkeyed-1 = "<leader>fr";
            __unkeyed-2 = "<cmd>FzfLua oldfiles<cr>";
            desc = "Recent Files";
          }
          {
            __unkeyed-1 = "<leader>fh";
            __unkeyed-2 = "<cmd>FzfLua helptags<cr>";
            desc = "Help";
          }
          {
            __unkeyed-1 = "<leader>f.";
            __unkeyed-2 = "<cmd>FzfLua blines<cr>";
            desc = "Buffer Lines";
          }
          {
            __unkeyed-1 = "<leader>fs";
            __unkeyed-2.__raw = "function() _G.select_onedark_style() end";
            desc = "Select OneDark Style";
          }
        ];
      };
    };
    settings = {
      winopts = {
        border = "rounded";
        hls = {
          normal = "NormalFloat";
          border = "FloatBorder";
          title = "FloatTitle";
          preview_normal = "NormalFloat";
          preview_border = "FloatBorder";
        };
      };
      file_icon_padding = " ";
      files = {
        prompt = "Files❯ ";
        file_icons = true;
        git_icons = true;
      };
      previewers.bat = {
        cmd = "bat";
        args = "--style=numbers,changes --color always";
      };
    };
  };

  extraConfigLua = ''
    vim.ui.select = function(items, opts, on_choice)
      require("lz.n").trigger_load("fzf-lua")
      require("fzf-lua").register_ui_select()
      return vim.ui.select(items, opts, on_choice)
    end
  '';
}
