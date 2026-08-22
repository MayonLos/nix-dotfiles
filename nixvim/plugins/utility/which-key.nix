{
  plugins.which-key = {
    enable = true;
    settings = {
      spec = [
        {
          __unkeyed-1 = "<leader>f";
          group = "󰍉 Find";
        }
        {
          __unkeyed-1 = "<leader>s";
          group = "󰛔 Search";
        }
        {
          __unkeyed-1 = "<leader>g";
          group = "󰊢 Git";
        }
        {
          __unkeyed-1 = "<leader>l";
          group = "󰒋 LSP";
        }
        {
          __unkeyed-1 = "<leader>d";
          group = " Debug";
        }
        {
          __unkeyed-1 = "<leader>w";
          group = " Window";
          proxy = "<C-w>";
        }
        {
          __unkeyed-1 = "<leader>u";
          group = "󰒓 Utility / Toggle";
        }
        {
          __unkeyed-1 = "<leader>a";
          group = "󰚩 AI";
        }
        {
          __unkeyed-1 = "<leader>ac";
          group = "󰆍 CLI agent";
        }
        {
          __unkeyed-1 = "<leader>b";
          group = "󰓩 Buffer";
        }
        {
          __unkeyed-1 = "<leader>c";
          group = " Code";
        }
        {
          __unkeyed-1 = "<leader>n";
          group = "󰈙 Docs";
        }
        {
          __unkeyed-1 = "<leader>o";
          group = "󰏇 Oil";
        }
        {
          __unkeyed-1 = "<leader>t";
          group = " Terminal";
        }
        {
          __unkeyed-1 = "<leader>x";
          group = "󰔫 Diagnostics";
        }
        {
          __unkeyed-1 = "<leader>h";
          group = "󰛢 Harpoon";
        }
        {
          __unkeyed-1 = "<leader>p";
          group = "󰆓 Session";
        }
      ];
      win = {
        border = "rounded";
        wo = {
          winblend = 0;
        };
      };
    };
  };
}
