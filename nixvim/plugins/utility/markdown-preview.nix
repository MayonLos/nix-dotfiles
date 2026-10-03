{
  # render-markdown renders tables inline, but its output is terminal virtual
  # text: Neovim's own limits with wide/CJK glyphs are the ceiling there. This
  # is the escape hatch -- a real browser render of the current buffer, so
  # table alignment can always be checked against HTML instead of guessed.
  plugins.markdown-preview = {
    enable = true;

    lazyLoad.settings = {
      cmd = [
        "MarkdownPreview"
        "MarkdownPreviewStop"
        "MarkdownPreviewToggle"
      ];
      keys = [
        {
          __unkeyed-1 = "<leader>nm";
          __unkeyed-2 = "<cmd>MarkdownPreviewToggle<cr>";
          desc = "Markdown preview (browser)";
        }
      ];
    };

    settings = {
      auto_close = 1;
      echo_preview_url = 1;
    };
  };
}
