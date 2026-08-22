{
  # Replaces the one-line cmdline and the message area at the bottom of the
  # screen with floating windows. This is the single largest visual change in
  # the appearance group — everything else here decorates the buffer, this one
  # changes the frame around it.
  plugins.noice = {
    enable = true;

    settings = {
      # fidget.nvim already owns LSP progress (plugins/lsp/fidget.nix); leaving
      # this on gives two progress spinners for the same request.
      lsp.progress.enabled = false;

      # blink.cmp owns completion. noice's popupmenu would draw a second menu
      # over blink's.
      popupmenu.enabled = false;

      lsp.override = {
        "vim.lsp.util.convert_input_to_markdown_lines" = true;
        "vim.lsp.util.stylize_markdown" = true;
        "cmp.entry.get_documentation" = true;
      };

      presets = {
        # Search stays on the bottom line — a centred search box loses the
        # relationship between the pattern and the matches under it.
        bottom_search = true;
        # `:` opens centred, which is where the eye already is.
        command_palette = true;
        long_message_to_split = true;
        # Hover and signature help get a border rather than bleeding into the
        # buffer text behind them.
        lsp_doc_border = true;
        inc_rename = false;
      };

      routes = [
        # "written", "N more lines", "search hit BOTTOM" and friends fire on
        # nearly every keystroke sequence; they are noise once messages are a
        # popup rather than a status line you can ignore.
        {
          filter = {
            event = "msg_show";
            any = [
              { find = "%d+L, %d+B"; }
              { find = "; after #%d+"; }
              { find = "; before #%d+"; }
              { find = "%d fewer lines"; }
              { find = "%d more lines"; }
              { find = "written"; }
            ];
          };
          opts.skip = true;
        }
      ];
    };
  };

  # `vim.notify` is owned by snacks.notifier (see snacks.nix), which is what
  # noice routes messages into. nvim-notify used to sit here; snacks replaced
  # it, and both are folke's, so the handoff is the supported path.

  keymaps = [
    {
      mode = "n";
      key = "<leader>uh";
      action = "<cmd>NoiceHistory<cr>";
      options.desc = "Message history";
    }
    {
      mode = "n";
      key = "<leader>uD";
      action = "<cmd>NoiceDismiss<cr>";
      options.desc = "Dismiss notifications";
    }
    {
      mode = "n";
      key = "<leader>ue";
      action = "<cmd>NoiceErrors<cr>";
      options.desc = "Error messages";
    }
  ];
}
