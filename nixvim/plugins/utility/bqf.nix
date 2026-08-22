{ pkgs, ... }:
{
  extraPlugins = [ pkgs.vimPlugins.fzf-wrapper ];

  plugins.nvim-bqf = {
    enable = true;
    lazyLoad.settings.event = [
      "BufReadPost"
      "BufNewFile"
    ];
    settings = {
      preview = {
        border = "rounded";
        win_height = 14;
        win_vheight = 14;
        show_title = true;
      };
    };
  };
}
