{
  plugins.treesitter-context = {
    enable = true;

    lazyLoad.settings.event = [
      "BufReadPost"
      "BufNewFile"
    ];
    settings = {
      max_lines = 4;
      multiline_threshold = 1;
      trim_scope = "outer";
      mode = "cursor";
      separator = "─";
      zindex = 20;
    };
  };

  keymaps = [
    {
      mode = "n";
      key = "[c";
      action.__raw = ''function() require("treesitter-context").go_to_context(vim.v.count1) end'';
      options.desc = "Jump to context (upwards)";
    }
  ];
}
