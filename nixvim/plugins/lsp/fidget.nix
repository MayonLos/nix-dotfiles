{
  plugins.fidget = {
    enable = true;

    lazyLoad.settings.event = "LspAttach";
    settings = {
      progress.display = {
        done_icon = "";
        done_ttl = 3;
      };
      notification.window = {
        winblend = 0;
        border = "rounded";
      };
    };
  };
}
