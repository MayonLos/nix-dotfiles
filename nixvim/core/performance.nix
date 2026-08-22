{
  performance = {
    byteCompileLua = {
      enable = true;
      configs = true;
      plugins = true;
      nvimRuntime = true;
      luaLib = true;
    };

    combinePlugins = {
      enable = true;
      standalonePlugins = [
        "nvim-treesitter"
        # snacks ships its own queries/markdown/injections.scm, which collides
        # with nvim-treesitter's inside the merged pack directory. Keeping it
        # standalone is what this option is for.
        "snacks.nvim"
        "blink.cmp"
        "codecompanion.nvim"
        "mcphub.nvim"
      ];
    };
  };
}
