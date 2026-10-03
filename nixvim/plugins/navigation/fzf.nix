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
            __unkeyed-2.__raw = "function() _G.select_tokyonight_style() end";
            desc = "Select Tokyo Night Style";
          }
        ];
      };
    };
    settings = {
      # The default black backdrop (60) darkens the editor around the picker,
      # leaving a visible rectangle even when all picker backgrounds match.
      winopts = {
        backdrop = 100;
        border = "rounded";
        width = 0.86;
        height = 0.80;
        row = 0.5;
        col = 0.5;
        preview = {
          layout = "flex";
          horizontal = "right:55%";
          vertical = "down:45%";
          scrollbar = false;
        };
      };
      hls = {
        normal = "FzfLuaSurface";
        border = "FzfLuaSurfaceBorder";
        title = "FzfLuaSurfaceTitle";
        preview_normal = "FzfLuaSurface";
        preview_border = "FzfLuaSurfaceBorder";
        preview_title = "FzfLuaSurfaceTitle";
        fzf = {
          normal = "FzfLuaSurface";
          border = "FzfLuaSurfaceBorder";
          separator = "FzfLuaSurfaceBorder";
          gutter = "FzfLuaSurface";
          prompt = "FzfLuaSurfaceTitle";
          pointer = "FzfLuaSurfaceTitle";
          marker = "FzfLuaSurfaceTitle";
        };
      };
      fzf_colors = true;
      fzf_opts = {
        "--pointer" = "▌";
        "--marker" = "✓";
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
