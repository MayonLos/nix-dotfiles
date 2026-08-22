{ lib, ... }:
{
  plugins.vim-matchup = {
    enable = true;

    lazyLoad.settings.event = [
      "BufReadPost"
      "BufNewFile"
    ];
    settings = {
      matchparen_offscreen.method = "popup";
      surround_enabled = 1;
      transmute_enabled = 1;
    };
  };

  plugins.treesitter.settings.matchup.enable = lib.mkForce true;
}
