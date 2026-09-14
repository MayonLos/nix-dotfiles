_: {
  plugins.blink-cmp-latex.enable = true;

  plugins.blink-cmp = {
    enable = true;
    settings = {
      keymap = {
        preset = "enter";
        "<C-space>" = [
          "show"
          "show_documentation"
          "hide_documentation"
        ];
        "<C-e>" = [
          "cancel"
          "fallback"
        ];
        "<Up>" = [
          "select_prev"
          "fallback"
        ];
        "<Down>" = [
          "select_next"
          "fallback"
        ];
        "<C-b>" = [
          "scroll_documentation_up"
          "fallback"
        ];
        "<C-f>" = [
          "scroll_documentation_down"
          "fallback"
        ];
        "<Tab>" = [
          "snippet_forward"
          "select_next"
          "fallback"
        ];
        "<S-Tab>" = [
          "snippet_backward"
          "select_prev"
          "fallback"
        ];
        "<C-k>" = [
          "show_signature"
          "hide_signature"
          "fallback"
        ];
      };
      completion = {
        menu = {
          border = "rounded";
          draw = {
            padding = 1;
            gap = 1;
            treesitter = [ "lsp" ];
            columns = [
              { __unkeyed-1 = "label"; }
              {
                __unkeyed-1 = "kind_icon";
                __unkeyed-2 = "kind";
                gap = 1;
              }
              { __unkeyed-1 = "source_name"; }
            ];
          };
        };
        trigger.show_in_snippet = false;
        documentation = {
          auto_show = true;
          window.border = "rounded";
        };
        accept.auto_brackets.enabled = false;
      };
      sources = {
        per_filetype.codecompanion.__raw = ''{ "codecompanion", inherit_defaults = true }'';
        per_filetype.markdown.__raw = ''{ "latex", inherit_defaults = true }'';
        per_filetype.tex.__raw = ''{ "latex", inherit_defaults = true }'';
        providers.latex = {
          name = "LaTeX";
          module = "blink-cmp-latex";
          # The vault has 3564 LaTeX spans in 113 Markdown files (2026-09-14).
          # md_latex.lua consumes source, so insert \frac, not a Unicode symbol.
          # Only markdown/tex opt into this source; code completion stays scoped.
          opts.insert_command = true;
        };
        providers.codecompanion = {
          name = "CodeCompanion";
          module = "codecompanion.providers.completion.blink";
          score_offset = 100;
        };
      };

      snippets.preset = "luasnip";
      signature = {
        enabled = true;
        window.border = "rounded";
      };
    };
  };
}
