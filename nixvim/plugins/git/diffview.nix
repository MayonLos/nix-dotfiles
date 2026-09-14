{ pkgs, ... }:
{
  plugins.diffview = {
    enable = true;
    # The fork keeps require("diffview").setup and the Diffview commands,
    # so the nixvim module's settings and lz-n integration still apply.
    package = pkgs.callPackage ../../../pkgs/diffview-plus.nix { };
    lazyLoad = {
      enable = true;
      settings.cmd = [
        "DiffviewOpen"
        "DiffviewFileHistory"
        "DiffviewClose"
      ];
    };
  };

  keymaps = [
    {
      mode = "n";
      key = "<leader>gD";
      action = "<cmd>DiffviewOpen HEAD<cr>";
      options.desc = "Diff against HEAD";
    }
    {
      mode = "n";
      key = "<leader>gH";
      action = "<cmd>DiffviewFileHistory %<cr>";
      options.desc = "Current file history";
    }
    {
      mode = "n";
      key = "<leader>gC";
      action = "<cmd>DiffviewClose<cr>";
      options.desc = "Close diff view";
    }
  ];
}
