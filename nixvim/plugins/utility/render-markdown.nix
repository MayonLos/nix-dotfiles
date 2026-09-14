{ pkgs, ... }:
let
  latexConverter = pkgs.writeShellScript "md-utftex" ''
    set -euo pipefail
    ${pkgs.luajit}/bin/luajit -e '
      local expr = dofile("${./lua/md_latex.lua}").preprocess(io.read("*a"))
      if not expr then os.exit(1) end
      io.write(expr)
    ' | utftex
  '';
in
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

      # The builtin's converter list defaults to utftex then latex2text in
      # render-markdown 8.12.0; all five operator probes lost their operator in
      # the latter. md_latex now gates display roots too and owns that fallback.
      #
      # Also set through globals.render_markdown_config below -- this line alone
      # is not enough, see the comment there.
      latex.converter = "${latexConverter}";

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

  # The first markdown buffer of a session rendered with the *default*
  # converter list no matter what `settings.latex.converter` said, so every
  # \boxed formula in it fell through to latex2text and came back with its
  # relation silently dropped -- the exact corruption md_latex exists to
  # prevent. Every buffer after the first was fine.
  #
  # plugin/render-markdown.lua calls setup(vim.g.render_markdown_config) when
  # the plugin directory is sourced, and lz-n defers that to the FileType that
  # opens the first markdown buffer. The manager attaches and renders straight
  # away, so the render context captures a buffer config built from the
  # defaults; nixvim's own setup() with the real settings lands after it.
  # `custom_handlers` is read live off a module field rather than the captured
  # config, which is why md_latex still ran that pass and only the converter
  # was stale -- and the builtin caches converter output globally by formula
  # text, so the wrong string then outlived the race for the whole session.
  #
  # Setting the global is the plugin's own answer to plugin-manager ordering:
  # the plugin-directory setup picks it up, so the converter is already right
  # in that window. nixvim's setup runs afterwards with the same value.
  globals.render_markdown_config.latex.converter = "${latexConverter}";

  extraFiles = {
    "lua/md_latex.lua".source = ./lua/md_latex.lua;
  };
}
