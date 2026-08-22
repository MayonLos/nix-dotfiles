{
  plugins.gitsigns = {
    enable = true;
    lazyLoad = {
      enable = true;
      settings.event = [
        "BufReadPost"
        "BufNewFile"
      ];
    };
  };

  keymaps =
    let
      gs = body: { __raw = "function() require('gitsigns').${body} end"; };
      mkMap = mode: key: action: desc: {
        inherit mode key action;
        options.desc = desc;
      };
    in
    [
      (mkMap "n" "]h" (gs "nav_hunk('next')") "Next git hunk")
      (mkMap "n" "[h" (gs "nav_hunk('prev')") "Prev git hunk")
      (mkMap "n" "<leader>gs" (gs "stage_hunk()") "Stage/unstage hunk")
      (mkMap "v" "<leader>gs" (gs "stage_hunk({ vim.fn.line('.'), vim.fn.line('v') })") "Stage selection")
      (mkMap "n" "<leader>gr" (gs "reset_hunk()") "Reset hunk")
      (mkMap "v" "<leader>gr" (gs "reset_hunk({ vim.fn.line('.'), vim.fn.line('v') })") "Reset selection")
      (mkMap "n" "<leader>gS" (gs "stage_buffer()") "Stage buffer")
      (mkMap "n" "<leader>gR" (gs "reset_buffer()") "Reset buffer")
      (mkMap "n" "<leader>gp" (gs "preview_hunk_inline()") "Preview hunk (inline)")
      (mkMap "n" "<leader>gb" (gs "blame_line({ full = true })") "Blame line")
      (mkMap "n" "<leader>gB" (gs "toggle_current_line_blame()") "Toggle line blame")
      (mkMap "n" "<leader>gd" (gs "diffthis()") "Diff against index")
      (mkMap "n" "<leader>gq" (gs "setqflist('all')") "All hunks to quickfix")
    ];
}
