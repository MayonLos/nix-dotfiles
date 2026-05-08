{ pkgs, ... }:

{
  programs.yazi = {
    enable = true;
    enableZshIntegration = true;
    shellWrapperName = "y";

    # Runtime binaries required by previewers/plugins
    extraPackages = with pkgs; [
      fd
      file
      poppler-utils       # PDF → text preview
      ffmpegthumbnailer   # video thumbnail frames
      mediainfo           # media metadata sidebar
      exiftool            # EXIF/file metadata
      duckdb              # CSV/JSON/Parquet table rendering
      glow                # Markdown terminal renderer
      ouch                # archive listing + compress/decompress
    ];

    plugins = with pkgs.yaziPlugins; {
      inherit
        # === Previewers ===
        duckdb            # tabular data as rendered tables
        glow              # Markdown → glow output
        ouch              # archive contents listing
        # === UI ===
        full-border       # rounded borders around all panels
        toggle-pane       # hide/show preview pane with one key
        # === Behavior ===
        smart-enter       # l/Enter = enter dir or open file (smarter)
        smart-filter      # F = filter that auto-enters sole result
        # === Navigation ===
        jump-to-char      # f → jump to next file starting with <char>
        relative-motions  # 1-5 → display relative numbers + jump N lines
        # === Integrations ===
        git               # git status badges on files and dirs
        # === File ops ===
        chmod             # interactive octal permission editor
        ;
    };

    # init.lua — executed once at startup; wire up plugins that need setup()
    initLua = ''
      require("full-border"):setup {
        type = ui.Border.ROUNDED,
      }

      require("git"):setup {
        order = 1500,
      }

      require("smart-enter"):setup {
        open_multi = true,
      }

      require("relative-motions"):setup {
        show_numbers = "relative",
        show_motion  = true,
      }
    '';

    settings = {
      mgr = {
        ratio        = [ 1 4 3 ];
        sort_by      = "natural";
        sort_sensitive = true;
        sort_reverse  = false;
        sort_dir_first = true;
        show_hidden   = true;
        show_symlink  = true;
        scrolloff     = 5;
      };

      preview = {
        image_filter  = "lanczos3";
        image_quality = 90;
        tab_size      = 2;
        max_width     = 600;
        max_height    = 900;
      };

      tasks = {
        micro_workers = 5;
        macro_workers = 10;
        bizarre_retry = 5;
      };

      opener = {
        edit = [
          { run = ''nvim "$@"''; block = true; }
        ];
      };

      plugin = {
        # --- Previewers (prepend = checked before built-ins) ---
        prepend_previewers = [
          # Tabular data rendered as tables via duckdb
          { name = "*.csv";     run = "duckdb"; }
          { name = "*.tsv";     run = "duckdb"; }
          { name = "*.json";    run = "duckdb"; }
          { name = "*.parquet"; run = "duckdb"; }
          { name = "*.arrow";   run = "duckdb"; }
          # Markdown rendered by glow
          { name = "*.md";       run = "glow"; }
          { name = "*.markdown"; run = "glow"; }
          # Archives listed by ouch (mime-based, covers all variants)
          { mime = "application/{*zip,tar,bzip2,7z*,rar,xz,zstd,java-archive}"; run = "ouch"; }
        ];

        # --- Fetchers: git status badges (correct API for yazi 25.5.x) ---
        prepend_fetchers = [
          { id = "git"; name = "*";  run = "git"; }
          { id = "git"; name = "*/"; run = "git"; }
        ];
      };
    };

    keymap = {
      mgr.prepend_keymap = [
        # === Entry behavior ===
        # l and Enter both use smart-enter (replaces default l/Enter)
        { on = "l";       run = "plugin smart-enter"; desc = "Enter dir or open file"; }
        { on = "<Enter>"; run = "plugin smart-enter"; desc = "Enter dir or open file"; }

        # === Filtering ===
        # F → smart-filter (auto-enters sole match; replaces default f/F filter)
        { on = "F"; run = "plugin smart-filter"; desc = "Smart filter"; }

        # === Preview ===
        { on = "!"; run = "plugin toggle-pane"; desc = "Toggle preview pane"; }

        # === Navigation ===
        # f → jump to next file whose name starts with a typed char (vim-style)
        { on = "f"; run = "plugin jump-to-char"; desc = "Jump to char"; }
        # 1-5 → show relative line numbers and jump N steps
        { on = "1"; run = "plugin relative-motions 1"; desc = "×1 relative motion"; }
        { on = "2"; run = "plugin relative-motions 2"; desc = "×2 relative motion"; }
        { on = "3"; run = "plugin relative-motions 3"; desc = "×3 relative motion"; }
        { on = "4"; run = "plugin relative-motions 4"; desc = "×4 relative motion"; }
        { on = "5"; run = "plugin relative-motions 5"; desc = "×5 relative motion"; }

        # === File operations ===
        # C → compress selection or decompress hovered archive
        { on = "C"; run = "plugin ouch"; desc = "Compress / decompress (ouch)"; }
        # gm → interactive chmod editor
        { on = [ "g" "m" ]; run = "plugin chmod"; desc = "chmod selected files"; }
        # Ctrl+s → drop into $SHELL at current path
        { on = "<C-s>"; run = ''shell "$SHELL" --block''; desc = "Shell in current dir"; }

        # === Tabs ===
        { on = "T"; run = "tab_create --current"; desc = "New tab at current path"; }

        # === Misc ===
        { on = "<C-r>"; run = "reload"; desc = "Reload current directory"; }
      ];
    };
  };
}
