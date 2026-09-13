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

      # utftex renders a formula as a box several rows tall. render-markdown
      # puts those extra rows in virt_lines around the *buffer* line, which is
      # right for a display block on its own line and unreadable for inline
      # maths in wrapped prose -- numerator and denominator end up on opposite
      # sides of the paragraph. md_latex.lua decides per formula which of the
      # two it is; the converters come from toolchain.nix.
      custom_handlers.latex.parse.__raw = ''
        function(ctx)
          return require("md_latex").parse(ctx)
        end
      '';

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

  extraFiles = {
    "lua/md_latex.lua".source = ./lua/md_latex.lua;
  };
}
