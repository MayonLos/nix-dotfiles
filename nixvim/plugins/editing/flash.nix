{
  plugins.flash = {
    enable = true;
    settings = { };
  };

  keymaps = [
    {
      mode = [
        "n"
        "x"
        "o"
      ];
      key = "s";
      action.__raw = "function() require('flash').jump() end";
      options.desc = "Flash jump";
    }
    # Normal and operator-pending only. nvim-surround registers visual `S`
    # inside its own setup(), which runs after init.lua's keymaps, so a visual
    # `S` here lost every time -- measured: maparg("S","x") was nvim-surround's
    # "Add a surrounding pair around a visual selection". Surround keeps it;
    # it is the standard vim-surround binding and the higher-frequency one.
    # Visual treesitter selection is still on `R` (treesitter_search) below.
    {
      mode = [
        "n"
        "o"
      ];
      key = "S";
      action.__raw = "function() require('flash').treesitter() end";
      options.desc = "Flash treesitter select";
    }
    {
      mode = "o";
      key = "r";
      action.__raw = "function() require('flash').remote() end";
      options.desc = "Remote flash";
    }
    {
      mode = [
        "o"
        "x"
      ];
      key = "R";
      action.__raw = "function() require('flash').treesitter_search() end";
      options.desc = "Treesitter search";
    }
  ];
}
