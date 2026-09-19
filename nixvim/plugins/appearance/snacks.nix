_: {
  # One plugin replacing five. dressing.nvim was the forcing function — its
  # author archived it with "use snacks.nvim instead for your vim.ui.*
  # interfaces" — and once snacks is here, nvim-notify, neoscroll,
  # indent-blankline and vim-illuminate are all a sub-module of it.
  #
  # Only the modules named below are enabled. picker is on solely because
  # explorer is built on it — see the `ui_select = false` note down there.
  plugins.snacks = {
    enable = true;

    settings = {
      # --- replacements -------------------------------------------------
      input = {
        enabled = true; # was dressing.nvim
        win.border = "rounded";
      };
      styles.notification = {
        border = "rounded";
        wo.winblend = 0;
      };

      notifier = {
        enabled = true; # was nvim-notify
        timeout = 2500;
        style = "compact";
        top_down = false; # bottom-up, so it does not cover the buffer top
      };

      scroll = {
        enabled = true; # was neoscroll.nvim
        animate = {
          # Short enough that it never reads as waiting for the editor.
          duration = {
            step = 12;
            total = 180;
          };
          easing = "outQuad";
        };
      };

      indent = {
        enabled = true; # was indent-blankline.nvim
        animate.enabled = false; # animated guides are a distraction, not a cue
        indent.char = "│";
        scope = {
          enabled = true; # draw the enclosing scope, not just columns
          char = "│";
        };
      };

      words = {
        enabled = true; # was vim-illuminate
        debounce = 150;
      };

      # --- new ----------------------------------------------------------
      # Not the same thing as `indent.scope` above, which only draws a line.
      # This one computes the scope under the cursor and exposes it as text
      # objects and as jumps — treesitter-aware, falling back to indentation in
      # filetypes with no parser.
      #
      # Its text objects are deliberately left unbound: treesitter-textobjects
      # already owns `ii`/`ai` and is the more precise of the two. What scope
      # adds here is the detection behind `indent.scope` above, plus the
      # `[i`/`]i` jumps.
      scope.enabled = true;

      # Turns treesitter, LSP and syntax off above the threshold. Opening a
      # generated file or a big log used to lock the editor for seconds.
      bigfile = {
        enabled = true;
        size = 1048576; # 1 MiB
      };

      # Paints the file before the plugin stack finishes loading, so `nvim
      # <file>` shows text immediately rather than an empty frame.
      quickfile.enabled = true;

      # Dims everything outside the current scope. Off by default — it is a
      # mode you enter (<leader>ud), not something to leave running.
      dim.enabled = true;

      zen.enabled = true;

      # heirline draws the statusline and the tabline; it never touched the
      # status *column*, which was Neovim's built-in default. That default has
      # no fold indicator, so a folded region was invisible until you moved
      # onto it. ufo now manages the Treesitter fold ranges (editing/ufo.nix);
      # this remains the sole fold indicator, with the native foldcolumn off.
      statuscolumn = {
        enabled = true;
        left = [
          "mark"
          "sign"
        ];
        right = [
          "fold"
          "git"
        ];
        folds = {
          open = true; # show the marker on open folds too, not only closed ones
          git_hl = true; # colour it with the git status of the folded range
        };
        # gitsigns places its signs under this name; without the pattern its
        # marks would render in the left group alongside diagnostics instead of
        # in the dedicated git column on the right.
        git.patterns = [ "GitSign" ];
        refresh = 50;
      };

      # Everything else stays off explicitly rather than by omission, so a
      # snacks release that flips a default on cannot change this config.
      # explorer is built on picker, so picker has to be on for the tree to
      # exist at all. `ui_select = false` is the load-bearing part: picker
      # otherwise claims vim.ui.select, which fzf-lua already owns
      # (plugins/navigation/fzf.nix registers it), and the two would fight over
      # every selection prompt.
      picker = {
        enabled = true;
        ui_select = false;
      };
      explorer.enabled = true;

      # Enabled on 2026-09-19, when the terminal moved from foot to kitty
      # (modules/home/programs/terminal/kitty.nix). snacks/image/terminal.lua
      # speaks kitty, ghostty and wezterm only -- foot implements sixel and
      # nothing else, so this rendered exactly zero images and was off.
      #
      # The payload is not really pictures, it is *maths*:
      # snacks/image/init.lua:137-165 builds a LaTeX `standalone` document
      # (amsmath, amssymb, amsfonts, amscd, mathtools), renders it with
      # pdflatex -- texliveFull from programs/dev/latex.nix -- and converts at
      # `-density 192 -trim` with ImageMagick from packages.nix. Both binaries
      # were already on PATH. It colours the output to the current palette, so
      # formulae inherit the theme.
      #
      # utftex (plugins/utility/render-markdown.nix) stays as the fallback for
      # anywhere the graphics protocol is unavailable -- a plain tty, or ssh
      # without `kitten ssh`.
      # Every key of `doc` is spelled out, including the ones that only repeat
      # a snacks default. Setting this table at all risks replacing rather
      # than merging, and the default it would drop is `conceal` -- the
      # function that hides the `$...$` source once its image is placed
      # (snacks/image/init.lua:84-91). Lose that and the source and the image
      # sit side by side, which looks like the renderer is broken.
      image = {
        enabled = true;
        doc = {
          enabled = true;

          # Formulae typeset *in the buffer*, which is the whole point of
          # writing them. `float` is listed for completeness only: in a
          # terminal that speaks the graphics protocol, snacks resolves
          # `float = doc.float and not inline` (image/doc.lua:445-446), so
          # inline wins and the two can never both be on.
          #
          # The cost, and it is a real one: a formula inside a markdown table
          # still breaks that table's alignment. render-markdown measures a
          # column from the *character* width of the text it conceals
          # (render/markdown/table.lua:183-190 via request/context.lua:40-47,
          # which counts only render-markdown's own extmarks), while snacks
          # sizes the inline placeholder from the rendered PNG's *pixels*
          # (image/util.lua:50-61). Neither can see the other's numbers. No
          # snacks option fixes it -- `math.latex.font_size` only makes the
          # error smaller, not zero, and a different size per formula means a
          # different error per row.
          #
          # Set `inline = false` to trade typeset-in-place back for intact
          # tables; snacks then falls back to a hover float.
          inline = true;
          float = true;

          max_width = 80;
          max_height = 40;

          # snacks' own default, restated (init.lua:88-91): conceal the source
          # of a maths block, leave an image link's source alone.
          conceal.__raw = ''
            function(_lang, type)
              return type == "math"
            end
          '';
        };
        math = {
          enabled = true;
          # "Large" is snacks' default and it is sized for a formula sitting
          # alone on its own line. In prose and especially inside a table it
          # dwarfs the text around it -- measured against the real notes, a
          # single inline \$...\$ was taller than three rows of the table it
          # was in. "small" keeps a display block readable while letting an
          # inline formula sit closer to the line height of the text.
          latex.font_size = "small";
        };
      };

      dashboard.enabled = false;

      # terminal replaced toggleterm (unmaintained: last commit 2025-03).
      # Unlike every other key in this block this is not an on/off switch --
      # snacks/init.lua only auto-starts the modules listed in its `events`
      # table and terminal is not one of them, so `enabled` is never read here.
      # What this block actually does is set the defaults every
      # Snacks.terminal() call merges through Snacks.config.get("terminal", ...).
      #
      # position must be spelled out: snacks/terminal.lua M.open resolves it as
      # `cmd and "float" or "bottom"`, so a bare toggle with no command would
      # open a bottom split, not the float toggleterm gave us.
      terminal = {
        win = {
          position = "float";
          # toggleterm called this "curved"; that name is toggleterm's own.
          # snacks passes the value straight to nvim_open_win, which spells the
          # same border "rounded".
          border = "rounded";
          width = 120;
          height = 30;
        };
      };
    };
  };

  keymaps = [
    # --- git ------------------------------------------------------------
    {
      mode = "n";
      key = "<leader>gg";
      action.__raw = ''function() require("snacks").lazygit() end'';
      options.desc = "Lazygit";
    }
    {
      mode = [
        "n"
        "v"
      ];
      key = "<leader>go";
      action.__raw = ''function() require("snacks").gitbrowse() end'';
      options.desc = "Open line on remote";
    }

    # --- file -----------------------------------------------------------
    {
      # Renaming through the tree or through `:!mv` does not tell the language
      # server, so every import pointing at the old name silently breaks. This
      # one goes through the LSP's willRenameFiles.
      mode = "n";
      key = "<leader>fR";
      action.__raw = ''function() require("snacks").rename.rename_file() end'';
      options.desc = "Rename file (LSP-aware)";
    }

    # --- explorer -------------------------------------------------------
    {
      # The file manager for this config. oil.nvim used to sit beside it as the
      # "edit the directory as a buffer" surface and was removed on 2026-09-18:
      # two file explorers, and the one that was supposed to own `nvim <dir>`
      # never did -- its `default_file_explorer = true` needed oil loaded to
      # register the netrw hijack, but oil was lazy on `cmd = "Oil"` while this
      # one is eager, so snacks claimed the directory buffer every time
      # (measured: `nvim dtest/` gave ft=snacks_picker_list, oil not loaded).
      mode = "n";
      key = "<leader>e";
      action.__raw = ''function() require("snacks").explorer() end'';
      options.desc = "File tree";
    }

    # --- scope ----------------------------------------------------------
    # snacks' own `scope.keys.jump` config produced no keymaps in 2.31 — the
    # entries reach `Snacks.config` but nothing registers them — so these call
    # the API directly rather than trusting that indirection.
    {
      mode = [
        "n"
        "x"
      ];
      key = "[i";
      action.__raw = ''function() require("snacks").scope.jump({ bottom = false }) end'';
      options.desc = "Jump to top of scope";
    }
    {
      mode = [
        "n"
        "x"
      ];
      key = "]i";
      action.__raw = ''function() require("snacks").scope.jump({ bottom = true }) end'';
      options.desc = "Jump to bottom of scope";
    }

    # --- utility / toggles ----------------------------------------------
    {
      mode = "n";
      key = "<leader>us";
      action.__raw = ''function() require("snacks").scratch() end'';
      options.desc = "Scratch buffer";
    }
    {
      mode = "n";
      key = "<leader>uS";
      action.__raw = ''function() require("snacks").scratch.select() end'';
      options.desc = "Select scratch buffer";
    }
    {
      mode = "n";
      key = "<leader>uz";
      action.__raw = ''function() require("snacks").zen() end'';
      options.desc = "Zen mode";
    }
    {
      mode = "n";
      key = "<leader>ud";
      action.__raw = ''function() require("snacks").dim() end'';
      options.desc = "Dim inactive scope";
    }
    {
      mode = "n";
      key = "<leader>un";
      action.__raw = ''function() require("snacks").notifier.show_history() end'';
      options.desc = "Notification history";
    }
  ];

  # Snacks.toggle builds a keymap that also reports its own state — which-key
  # shows it as on/off instead of as a command name, and the notification says
  # which way it just went. Hand-written `set invwrap` bindings cannot do that.
  extraConfigLua = ''
    local Snacks = require("snacks")

    -- `input.enabled = true` above only writes snacks' config table; it does
    -- not claim vim.ui.input. Same mechanism as the terminal block: snacks
    -- auto-starts only the modules listed in its own `events` table, and input
    -- is not one of them. Measured on 2.31.0 -- vim.ui.input resolves to
    -- runtime/lua/vim/ui.lua before this call and to snacks/input.lua after,
    -- so without it every rename prompt falls back to the command line and the
    -- rounded border configured above is never drawn.
    Snacks.input.enable()

    Snacks.toggle.option("wrap", { name = "Wrap" }):map("<leader>uw")
    Snacks.toggle.option("spell", { name = "Spelling" }):map("<leader>up")
    Snacks.toggle.option("relativenumber", { name = "Relative number" }):map("<leader>ur")
    Snacks.toggle.diagnostics():map("<leader>ux")
    Snacks.toggle.inlay_hints():map("<leader>ui")
    Snacks.toggle.treesitter():map("<leader>ut")
  '';
}
