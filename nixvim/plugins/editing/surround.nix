{
  plugins.nvim-surround = {
    enable = true;
    lazyLoad = {
      enable = true;
      settings.event = [
        "BufReadPost"
        "BufNewFile"
      ];
    };
  };
}
