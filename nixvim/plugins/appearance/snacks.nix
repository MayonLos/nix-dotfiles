{
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
      input.enabled = true; # was dressing.nvim

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
        scope.enabled = true; # draw the enclosing scope, not just columns
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
      # no fold indicator, and this config folds by treesitter expression
      # (plugins/editing/treesitter.nix sets folding.enable), so a folded
      # region was invisible until you moved onto it.
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

      # image needs the kitty graphics protocol — snacks/image/terminal.lua
      # detects only kitty, ghostty and wezterm, and `grep -ri sixel` across the
      # module returns nothing. foot implements sixel and nothing else, so this
      # would render exactly zero images.
      image.enabled = false;

      dashboard.enabled = false;
      terminal.enabled = false;
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
      # oil can rename a file too, but it will not tell the language server,
      # so every import pointing at the old name silently breaks.
      mode = "n";
      key = "<leader>fR";
      action.__raw = ''function() require("snacks").rename.rename_file() end'';
      options.desc = "Rename file (LSP-aware)";
    }

    # --- explorer -------------------------------------------------------
    {
      # A tree for orientation. oil stays the editing surface: it renames and
      # deletes by editing buffer text, which a tree cannot express.
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
    Snacks.toggle.option("wrap", { name = "Wrap" }):map("<leader>uw")
    Snacks.toggle.option("spell", { name = "Spelling" }):map("<leader>up")
    Snacks.toggle.option("relativenumber", { name = "Relative number" }):map("<leader>ur")
    Snacks.toggle.diagnostics():map("<leader>ux")
    Snacks.toggle.inlay_hints():map("<leader>ui")
    Snacks.toggle.treesitter():map("<leader>ut")
  '';
}
