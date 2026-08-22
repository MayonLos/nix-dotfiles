{
  plugins.toggleterm = {
    enable = true;

    lazyLoad.settings.cmd = [
      "ToggleTerm"
      "TermExec"
    ];

    settings = {
      direction = "float";
      float_opts = {
        border = "curved";
        width = 120;
        height = 30;
      };
      size = 15;
      start_in_insert = true;
      auto_scroll = true;
      winbar = {
        enabled = true;
        name_formatter.__raw = ''
          function(term)
            return "  Terminal #" .. term.id
          end
        '';
      };
    };
  };

  keymaps = [
    {
      mode = [
        "n"
        "t"
      ];
      key = "<C-\\>";
      action = "<cmd>ToggleTerm<cr>";
      options = {
        silent = true;
        desc = "Toggle Terminal";
      };
    }
    {
      mode = "n";
      key = "<leader>tf";
      action.__raw = "function() require('toggleterm').toggle(1, 15, nil, 'float') end";
      options = {
        silent = true;
        desc = "Float Terminal";
      };
    }
    {
      mode = "n";
      key = "<leader>th";
      action.__raw = "function() require('toggleterm').toggle(1, 15, nil, 'horizontal') end";
      options = {
        silent = true;
        desc = "Bottom Terminal";
      };
    }

    {
      mode = "t";
      key = "<C-h>";
      action = "<cmd>wincmd h<cr>";
      options = {
        silent = true;
        desc = "Terminal: left window";
      };
    }
    {
      mode = "t";
      key = "<C-j>";
      action = "<cmd>wincmd j<cr>";
      options = {
        silent = true;
        desc = "Terminal: lower window";
      };
    }
    {
      mode = "t";
      key = "<C-k>";
      action = "<cmd>wincmd k<cr>";
      options = {
        silent = true;
        desc = "Terminal: upper window";
      };
    }
    {
      mode = "t";
      key = "<C-l>";
      action = "<cmd>wincmd l<cr>";
      options = {
        silent = true;
        desc = "Terminal: right window";
      };
    }
    {
      mode = "t";
      key = "<Esc><Esc>";
      action = "<C-\\><C-n>";
      options = {
        silent = true;
        desc = "Terminal: normal mode";
      };
    }
  ];
}
