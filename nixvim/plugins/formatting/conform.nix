{
  plugins.conform-nvim = {
    enable = true;

    lazyLoad = {
      enable = true;
      settings = {
        event = [ "BufWritePre" ];
        cmd = [ "ConformInfo" ];
        keys = [
          {
            __unkeyed-1 = "<leader>lf";
            __unkeyed-2.__raw = ''
              function()
                require("conform").format({ async = true, lsp_format = "fallback" })
              end
            '';
            desc = "Format buffer (manual)";
          }
        ];
      };
    };

    luaConfig.pre = ''
      _G.slow_format_filetypes = {}
    '';

    settings = {
      formatters_by_ft = {
        lua = [ "stylua" ];
        python = [
          "ruff_organize_imports"
          "ruff_format"
        ];
        nix = [ "nixfmt" ];
        java = [ "google-java-format" ];
        c = [ "clang-format" ];
        cpp = [ "clang-format" ];
        bash = [ "shfmt" ];
        sh = [ "shfmt" ];
        tex = [ "latexindent" ];
        # MATLAB has no standalone formatter; matlab_ls formats by asking the
        # MATLAB it drives. The entry has to exist even though it lists no
        # formatter -- without it the `_` catch-all below claims .m buffers,
        # runs trim_whitespace, counts as a successful format, and the LSP is
        # never consulted. The first save then blows format_on_save's 200ms
        # budget while MATLAB starts; that is exactly what
        # _G.slow_format_filetypes handles, and from the second save on it
        # formats through format_after_save instead.
        matlab = {
          lsp_format = "prefer";
        };
        "_" = [
          "squeeze_blanks"
          "trim_whitespace"
          "trim_newlines"
        ];
      };

      format_on_save = ''
        function(bufnr)
          if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
            return
          end
          if _G.slow_format_filetypes[vim.bo[bufnr].filetype] then
            return
          end
          local function on_format(err)
            if err and err:match("timeout$") then
              _G.slow_format_filetypes[vim.bo[bufnr].filetype] = true
            end
          end
          return { timeout_ms = 200, lsp_format = "fallback" }, on_format
        end
      '';

      format_after_save = ''
        function(bufnr)
          if vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat then
            return
          end
          if not _G.slow_format_filetypes[vim.bo[bufnr].filetype] then
            return
          end
          return { lsp_format = "fallback" }
        end
      '';
    };
  };

  userCommands = {
    FormatDisable = {
      command = "lua vim.g.disable_autoformat = true";
      desc = "Disable autoformat-on-save";
    };
    FormatEnable = {
      command = "lua vim.g.disable_autoformat = false";
      desc = "Enable autoformat-on-save";
    };
  };
}
