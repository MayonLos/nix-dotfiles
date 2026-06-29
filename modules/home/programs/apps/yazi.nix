{ pkgs, ... }:

{
  programs.yazi = {
    enable = true;
    enableZshIntegration = true;
    shellWrapperName = "y";

    extraPackages = with pkgs; [
      fd
      file
      poppler-utils
      ffmpegthumbnailer
      mediainfo
      exiftool
      duckdb
      glow
      ouch
    ];

    plugins = with pkgs.yaziPlugins; {
      inherit
        duckdb
        glow
        ouch
        full-border
        toggle-pane
        smart-enter
        smart-filter
        jump-to-char
        relative-motions
        git
        chmod
        ;
    };

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
        ratio = [
          1
          4
          3
        ];
        sort_by = "natural";
        sort_sensitive = true;
        sort_reverse = false;
        sort_dir_first = true;
        show_hidden = true;
        show_symlink = true;
        scrolloff = 5;
      };

      preview = {
        image_filter = "lanczos3";
        image_quality = 90;
        tab_size = 2;
        max_width = 600;
        max_height = 900;
      };

      tasks = {
        micro_workers = 5;
        macro_workers = 10;
        bizarre_retry = 5;
      };

      opener = {
        edit = [
          {
            run = ''nvim "$@"'';
            block = true;
          }
        ];
      };

      plugin = {
        prepend_previewers = [
          {
            url = "*.csv";
            run = "duckdb";
          }
          {
            url = "*.tsv";
            run = "duckdb";
          }
          {
            url = "*.json";
            run = "duckdb";
          }
          {
            url = "*.parquet";
            run = "duckdb";
          }
          {
            url = "*.arrow";
            run = "duckdb";
          }
          {
            url = "*.md";
            run = "glow";
          }
          {
            url = "*.markdown";
            run = "glow";
          }
          {
            mime = "application/{*zip,tar,bzip2,7z*,rar,xz,zstd,java-archive}";
            run = "ouch";
          }
        ];

        prepend_fetchers = [
          {
            url = "*";
            run = "git";
            group = "git";
          }
          {
            url = "*/";
            run = "git";
            group = "git";
          }
        ];
      };
    };

    keymap = {
      mgr.prepend_keymap = [
        {
          on = "l";
          run = "plugin smart-enter";
          desc = "Enter dir or open file";
        }
        {
          on = "<Enter>";
          run = "plugin smart-enter";
          desc = "Enter dir or open file";
        }

        {
          on = "F";
          run = "plugin smart-filter";
          desc = "Smart filter";
        }

        {
          on = "!";
          run = "plugin toggle-pane";
          desc = "Toggle preview pane";
        }

        {
          on = "f";
          run = "plugin jump-to-char";
          desc = "Jump to char";
        }
        {
          on = "1";
          run = "plugin relative-motions 1";
          desc = "×1 relative motion";
        }
        {
          on = "2";
          run = "plugin relative-motions 2";
          desc = "×2 relative motion";
        }
        {
          on = "3";
          run = "plugin relative-motions 3";
          desc = "×3 relative motion";
        }
        {
          on = "4";
          run = "plugin relative-motions 4";
          desc = "×4 relative motion";
        }
        {
          on = "5";
          run = "plugin relative-motions 5";
          desc = "×5 relative motion";
        }

        {
          on = "C";
          run = "plugin ouch";
          desc = "Compress / decompress (ouch)";
        }
        {
          on = [
            "g"
            "m"
          ];
          run = "plugin chmod";
          desc = "chmod selected files";
        }
        {
          on = "<C-s>";
          run = ''shell "$SHELL" --block'';
          desc = "Shell in current dir";
        }

        {
          on = "T";
          run = "tab_create --current";
          desc = "New tab at current path";
        }

        {
          on = "<C-r>";
          run = "reload";
          desc = "Reload current directory";
        }
      ];
    };
  };
}
