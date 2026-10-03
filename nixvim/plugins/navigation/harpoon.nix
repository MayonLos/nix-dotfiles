let
  withHarpoon = body: ''
    function()
      require("lz.n").trigger_load("harpoon2")
      ${body}
    end
  '';
  select = index: withHarpoon ''require("harpoon"):list():select(${toString index})'';
in
{
  # fzf-lua answers "where is that file"; harpoon answers "the four files I am
  # actually working in right now". Different problem — a fuzzy finder still
  # costs a search per jump, and these jumps happen dozens of times an hour.
  plugins.harpoon = {
    enable = true;
    enableTelescope = false; # fzf-lua is the picker here, not telescope

    # 2.06 ms at startup was the single slowest require in this config, for a
    # plugin that does nothing until a <leader>h key is pressed.
    # The keys list only keeps the plugin lazy. nixvim applies `keymaps` after
    # lz-n's stubs and overwrites them, so each mapping has to trigger_load
    # itself. Measured for the same pattern in utility/persistence.nix.
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
      action.__raw = withHarpoon ''require("harpoon"):list():add()'';
      options.desc = "Harpoon: pin this file";
    }
    {
      mode = "n";
      key = "<leader>hh";
      action.__raw = withHarpoon ''
        local harpoon = require("harpoon")
        harpoon.ui:toggle_quick_menu(harpoon:list())
      '';
      options.desc = "Harpoon: pinned files";
    }
    {
      mode = "n";
      key = "<leader>h1";
      action.__raw = select 1;
      options.desc = "Harpoon: file 1";
    }
    {
      mode = "n";
      key = "<leader>h2";
      action.__raw = select 2;
      options.desc = "Harpoon: file 2";
    }
    {
      mode = "n";
      key = "<leader>h3";
      action.__raw = select 3;
      options.desc = "Harpoon: file 3";
    }
    {
      mode = "n";
      key = "<leader>h4";
      action.__raw = select 4;
      options.desc = "Harpoon: file 4";
    }
    {
      mode = "n";
      key = "<leader>hn";
      action.__raw = withHarpoon ''require("harpoon"):list():next()'';
      options.desc = "Harpoon: next";
    }
    {
      mode = "n";
      key = "<leader>hp";
      action.__raw = withHarpoon ''require("harpoon"):list():prev()'';
      options.desc = "Harpoon: previous";
    }
  ];
}
