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

      # Insert mode included. `render_modes` defaults to `{ "n", "c", "t" }`
      # (init.lua:60), so entering insert threw the *whole document* back to
      # raw source -- headings, tables, code blocks, all of it -- which is the
      # opposite of being able to see what you are writing. Seen on the real
      # notes: cursor in a formula on line 122, the maths float rendered fine
      # (that is lua/math_preview.lua and independent of this), while the
      # table three lines below sat there as `| 极点位置 | 时域响应 |`.
      #
      # `"v"` is deliberately left out. Visual mode is for selecting text by
      # its real extent, and rendering hides markup characters that a
      # selection has to include.
      render_modes = [
        "n"
        "c"
        "t"
        "i"
      ];

      # Two separate mechanisms un-render the line the cursor is on, and both
      # have to be turned off or the document comes apart as you walk through
      # it -- which is exactly what "the rendering breaks when I move" means.
      #
      # 1. This plugin owns `concealcursor` per window, not `nixvim/options.nix`.
      #    `win_options.concealcursor.rendered` defaults to "", and it is
      #    applied whenever rendering is on, so the global setting is
      #    overwritten the moment a markdown buffer opens. Verified with a live
      #    probe: `vim.wo.concealcursor` read "" in an open note while
      #    options.nix asked for "nvic". This is also what snacks' image layer
      #    reads (snacks/image/inline.lua:45) to decide whether to pull the
      #    formula images off the cursor's line, so the one setting governs
      #    both this plugin's conceal and the maths.
      # 2. `anti_conceal` un-renders this plugin's *own* marks near the cursor
      #    -- heading icons, bullets, table borders, link icons.
      #
      # The cost of both: while the cursor is on a line you do not see its raw
      # markup, so editing a link target or a table separator is done blind.
      # Drop the "i" from `concealcursor` to get the source back while actually
      # typing, or set `anti_conceal.enabled = true` to get this plugin's own
      # markup back without touching the maths.
      win_options.concealcursor.rendered = "nvic";
      anti_conceal.enabled = false;

      # Maths belongs to snacks.image now, not to this plugin.
      #
      # Both want the same `$$...$$` node, and this one wins: it conceals the
      # source and substitutes its converter's output before snacks can place
      # an image. Measured after the move to kitty -- snacks reported
      # `enabled=true math.enabled=true terminal=kitty supported=true`, and the
      # buffer still showed utftex's Unicode art. Same "two packages claiming
      # one canvas" shape as dirvish/nerd-icons and org-modern/valign in the
      # Emacs config.
      #
      # snacks renders the formula through pdflatex and shows a typeset image
      # (plugins/appearance/snacks.nix), which is what this is for.
      latex.enabled = false;

      # The utftex machinery below is kept, inert, as the documented fallback:
      # snacks needs the kitty graphics protocol, so a plain tty or an ssh
      # session without `kitten ssh` renders nothing. Flip `latex.enabled` back
      # to true there and this all works again, including the md_latex handler
      # that decides inline-vs-display -- do not delete it to "clean up".
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
