_: {
  plugins.fidget = {
    enable = true;

    lazyLoad.settings.event = "LspAttach";
    settings = {
      progress.display = {
        progress_icon = "⋯";
        done_icon = "✓";
        done_ttl = 1;
      };
      notification.window = {
        winblend = 0;
        border = "rounded";
        normal_hl = "NormalFloat";
        border_hl = "FloatBorder";
        # Snacks stacks notifications at the bottom; progress gets its own corner.
        align = "top";
      };
    };
  };
}
