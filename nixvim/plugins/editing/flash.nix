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
    {
      mode = [
        "n"
        "x"
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
