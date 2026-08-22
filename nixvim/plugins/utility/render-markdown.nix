{
  plugins.render-markdown = {
    enable = true;
    lazyLoad.settings.ft = [
      "markdown"
      "codecompanion"
    ];
    settings = {
      file_types = [
        "markdown"
        "codecompanion"
      ];
      completions.lsp.enabled = true;

      overrides.filetype.codecompanion = {
        heading = {
          width = "block";
          left_pad = 1;
          right_pad = 2;
          custom = {
            user = {
              pattern = "^##%s+Me";
              icon = "󰭹 ";
            };
            llm = {
              pattern = "^##%s+CodeCompanion";
              icon = "󰚩 ";
            };
          };
        };
        code = {
          width = "block";
          left_pad = 1;
          right_pad = 1;
        };
      };
    };
  };
}
