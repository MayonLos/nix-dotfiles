{
  # fzf-lua answers "where is that file"; harpoon answers "the four files I am
  # actually working in right now". Different problem — a fuzzy finder still
  # costs a search per jump, and these jumps happen dozens of times an hour.
  plugins.harpoon = {
    enable = true;
    enableTelescope = false; # fzf-lua is the picker here, not telescope

    # 2.06 ms at startup was the single slowest require in this config, for a
    # plugin that does nothing until a <leader>h key is pressed.
    lazyLoad.settings.keys = [
      "<leader>ha"
      "<leader>hh"
      "<leader>h1"
      "<leader>h2"
      "<leader>h3"
      "<leader>h4"
      "<leader>hn"
      "<leader>hp"
    ];
  };

  # `plugins.harpoon.keymaps` is deprecated in this nixvim release; the module
  # asks for plain keymaps calling the harpoon2 API directly.
  keymaps = [
    {
      mode = "n";
      key = "<leader>ha";
      action.__raw = ''function() require("harpoon"):list():add() end'';
      options.desc = "Harpoon: pin this file";
    }
    {
      mode = "n";
      key = "<leader>hh";
      action.__raw = ''
        function()
          local harpoon = require("harpoon")
          harpoon.ui:toggle_quick_menu(harpoon:list())
        end
      '';
      options.desc = "Harpoon: pinned files";
    }
    {
      mode = "n";
      key = "<leader>h1";
      action.__raw = ''function() require("harpoon"):list():select(1) end'';
      options.desc = "Harpoon: file 1";
    }
    {
      mode = "n";
      key = "<leader>h2";
      action.__raw = ''function() require("harpoon"):list():select(2) end'';
      options.desc = "Harpoon: file 2";
    }
    {
      mode = "n";
      key = "<leader>h3";
      action.__raw = ''function() require("harpoon"):list():select(3) end'';
      options.desc = "Harpoon: file 3";
    }
    {
      mode = "n";
      key = "<leader>h4";
      action.__raw = ''function() require("harpoon"):list():select(4) end'';
      options.desc = "Harpoon: file 4";
    }
    {
      mode = "n";
      key = "<leader>hn";
      action.__raw = ''function() require("harpoon"):list():next() end'';
      options.desc = "Harpoon: next";
    }
    {
      mode = "n";
      key = "<leader>hp";
      action.__raw = ''function() require("harpoon"):list():prev() end'';
      options.desc = "Harpoon: previous";
    }
  ];
}
