{
  palette ? null,
}:
{ pkgs, ... }:
let
  # Yazi accepts terminal ANSI names or RGB values. Use the user's shared
  # palette when it is wired in, with ANSI roles as a safe standalone fallback.
  colors =
    if palette == null then
      {
        black = "black";
        bg = "reset";
        deep = "darkgray";
        selection = "darkgray";
        border = "darkgray";
        fg = "white";
        brightFg = "white";
        muted = "darkgray";
        blue = "blue";
        cyan = "cyan";
        green = "green";
        yellow = "yellow";
        red = "red";
      }
    else
      palette;
in

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

    plugins =
      (with pkgs.yaziPlugins; {
        inherit
          duckdb
          ouch
          smart-enter
          smart-filter
          jump-to-char
          relative-motions
          git
          chmod
          ;
      })
      // {
        # The pinned glow plugin predates Yazi 26's singular Command/preview
        # APIs. Keep the adapter local and fail when upstream changes anchors.
        glow = pkgs.runCommand "glow.yazi-compatible" { } ''
          cp -R ${pkgs.yaziPlugins.glow} "$out"
          chmod -R u+w "$out"
          substituteInPlace "$out/main.lua" \
            --replace-fail ':args({' ':arg({' \
            --replace-fail 'ya.preview_widgets' 'ya.preview_widget' \
            --replace-fail 'require("code").peek(job)' 'require("code"):peek(job)' \
            --replace-fail 'ya.mgr_emit' 'ya.emit' \
            --replace-fail 'local preview_width = 55' 'local preview_width = job.area.w' \
            --replace-fail $'"--style",\n\t\t\t"dark",' '"--pager=false",'
        '';
        responsive-preview = pkgs.writeTextDir "main.lua" (
          builtins.readFile ./resources/yazi-responsive.lua
        );
      };

    initLua = ''
      require("responsive-preview"):setup { min_width = 100 }
      require("duckdb"):setup()

      -- The native header keeps the complete parent path even with no parent
      -- column. Separate its components as a breadcrumb, preserving filters.
      function Header:cwd()
        local max = self._area.w - self._right_width
        if max <= 0 then return "" end
        local path = ya.readable_path(tostring(self._current.cwd))
        local prefix = path:sub(1, 1) == "/" and "/ " or ""
        path = prefix .. path:gsub("^/", ""):gsub("/", " › ") .. self:flags()
        return ui.Span(ui.truncate(path, { max = max, rtl = true })):style(th.mgr.cwd)
      end

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
          0
          5
          4
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

    # The selected row and hovered preview receive separate cues. Colors are
    # the shared One Dark roles when available; named colors follow Kitty's
    # shared ANSI palette in standalone configurations.
    theme = {
      mgr = {
        cwd = {
          fg = colors.blue;
        };
        find_keyword = {
          fg = colors.yellow;
          bold = true;
        };
        marker_copied = {
          fg = colors.green;
          bg = colors.selection;
        };
        marker_cut = {
          fg = colors.yellow;
          bg = colors.selection;
        };
        marker_marked = {
          fg = colors.cyan;
          bg = colors.selection;
        };
        marker_selected = {
          fg = colors.blue;
          bg = colors.selection;
        };
        count_selected = {
          fg = colors.brightFg;
          bg = colors.selection;
        };
        border_style = {
          fg = colors.surface or "darkgray";
        };
      };

      tabs = {
        active = {
          fg = colors.blue;
          bg = colors.selection;
          bold = true;
        };
        inactive = {
          fg = colors.blue;
          bg = colors.deep;
        };
      };

      mode = {
        normal_main = {
          fg = colors.blue;
          bg = colors.selection;
          bold = true;
        };
        normal_alt = {
          fg = colors.blue;
          bg = colors.deep;
        };
        select_main = {
          fg = colors.green;
          bg = colors.selection;
          bold = true;
        };
        select_alt = {
          fg = colors.green;
          bg = colors.deep;
        };
        unset_main = {
          fg = colors.brightFg;
          bg = colors.selection;
          bold = true;
        };
        unset_alt = {
          fg = colors.red;
          bg = colors.deep;
        };
      };

      indicator = {
        # Yazi 26.5.6 exposes this as native indicator-bar padding. The left
        # glyph marks the hovered row; its current style carries blue/selection.
        padding = {
          open = "▎";
          close = "";
        };
        parent = {
          inherit (colors) fg;
          bg = colors.selection;
        };
        current = {
          fg = colors.blue;
          bg = colors.selection;
          bold = true;
        };
        preview = {
          underline = true;
        };
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
          run = "plugin responsive-preview";
          desc = "Toggle preview (automatic below 100 columns)";
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
