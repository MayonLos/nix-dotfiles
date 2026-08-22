{
  # Draws the actual colour behind #rrggbb, rgb() and friends. Only useful
  # where colours are written down, so it is scoped to those filetypes rather
  # than attached to every buffer.
  plugins.colorizer = {
    enable = true;

    lazyLoad = {
      enable = true;
      settings.ft = [
        "css"
        "scss"
        "html"
        "javascript"
        "typescript"
        "typescriptreact"
        "lua"
        "nix"
        "toml"
        "yaml"
        "conf"
      ];
    };

    settings = {
      user_default_options = {
        names = false; # "red"/"blue" as words match far too much prose
        css = true;
        css_fn = true;
        tailwind = true;
        # A swatch in the sign column would collide with gitsigns; render the
        # colour as the text background instead.
        mode = "background";
      };
    };
  };

  keymaps = [
    {
      mode = "n";
      key = "<leader>uc";
      action = "<cmd>ColorizerToggle<cr>";
      options.desc = "Toggle colour swatches";
    }
  ];
}
