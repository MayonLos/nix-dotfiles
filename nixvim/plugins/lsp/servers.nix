_: {
  # Every `cmd` below names its binary rather than interpolating a store path.
  # Two reasons: nvim and Emacs then start the *same* server, the one
  # modules/home/programs/dev/toolchain.nix installs; and a pinned path drags
  # the server into nvim's runtime closure — jdt-language-server alone brought
  # openjdk with it, 1.9 GiB for a binary the editor only ever exec's.
  lsp = {
    inlayHints.enable = true;

    servers = {
      clangd = {
        enable = true;
        package = null;
        config = {
          cmd = [
            "clangd"
            "--background-index"
            "--clang-tidy"
          ];
          filetypes = [
            "c"
            "cpp"
            "objc"
            "objcpp"
            "cuda"
          ];
          root_markers = [
            "compile_commands.json"
            ".clangd"
            "CMakeLists.txt"
            ".git"
          ];
        };
      };

      nixd = {
        enable = true;
        package = null;
        config = {
          cmd = [ "nixd" ];
          filetypes = [ "nix" ];
          root_markers = [
            "flake.nix"
            ".git"
          ];
          settings.nixd.formatting.command = [ "nixfmt" ];
        };
      };

      lua_ls = {
        enable = true;
        package = null;
        config = {
          cmd = [ "lua-language-server" ];
          filetypes = [ "lua" ];
          root_markers = [
            ".luarc.json"
            ".luarc.jsonc"
            ".stylua.toml"
            ".git"
          ];
          settings.Lua = {
            runtime.version = "LuaJIT";
            diagnostics.globals = [ "vim" ];
            # A workspace .luarc.json overrides this wholesale, which is what
            # non-neovim Lua projects want.
            workspace.library.__raw = "vim.api.nvim_get_runtime_file('', true)";
          };
        };
      };

      pyright = {
        enable = true;
        package = null;
        config = {
          cmd = [
            "pyright-langserver"
            "--stdio"
          ];
          filetypes = [ "python" ];
          root_markers = [
            "pyproject.toml"
            "setup.py"
            "setup.cfg"
            "requirements.txt"
            ".git"
          ];
        };
      };

      jdtls = {
        enable = true;
        package = null;
        config = {
          cmd = [ "jdtls" ];
          filetypes = [ "java" ];
          root_markers = [
            "pom.xml"
            "build.gradle"
            "settings.gradle"
            ".git"
          ];
        };
      };

      bashls = {
        enable = true;
        package = null;
        config = {
          cmd = [
            "bash-language-server"
            "start"
          ];
          filetypes = [
            "bash"
            "sh"
          ];
          root_markers = [ ".git" ];
        };
      };

      texlab = {
        enable = true;
        package = null;
        config = {
          cmd = [ "texlab" ];
          filetypes = [
            "tex"
            "plaintex"
            "bib"
          ];
          root_markers = [
            ".latexmkrc"
            ".git"
          ];
          settings.texlab = {
            bibtexFormatter = "texlab";
            chktex = {
              onOpenAndSave = true;
              onEdit = false;
            };
            diagnosticsDelay = 300;
            formatterLineLength = 100;
            inlayHints = {
              labelDefinitions = true;
              labelReferences = true;
            };
          };
        };
      };

      marksman = {
        enable = true;
        package = null;
        config = {
          cmd = [
            "marksman"
            "server"
          ];
          filetypes = [
            "markdown"
            "markdown.mdx"
          ];
          root_markers = [
            ".marksman.toml"
            ".git"
          ];
        };
      };

      cmake = {
        enable = true;
        package = null;
        config = {
          cmd = [ "cmake-language-server" ];
          filetypes = [ "cmake" ];
          root_markers = [
            "CMakeLists.txt"
            "CMakePresets.json"
            ".git"
          ];
        };
      };
    };

    keymaps = [
      {
        mode = "n";
        key = "gd";
        lspBufAction = "definition";
        options.desc = "Go to definition";
      }
      {
        mode = "n";
        key = "gD";
        lspBufAction = "declaration";
        options.desc = "Go to declaration";
      }
      {
        mode = "n";
        key = "gr";
        lspBufAction = "references";
        options.desc = "References";
      }
      {
        mode = "n";
        key = "grt";
        lspBufAction = "type_definition";
        options.desc = "Type definition";
      }
      {
        mode = "n";
        key = "gi";
        lspBufAction = "implementation";
        options.desc = "Implementation";
      }
      {
        mode = "n";
        key = "K";
        lspBufAction = "hover";
        options.desc = "Hover";
      }
      {
        mode = "n";
        key = "grx";
        action.__raw = "vim.lsp.codelens.run";
        options.desc = "Run codelens";
      }
      {
        mode = "n";
        key = "<leader>rn";
        lspBufAction = "rename";
        options.desc = "Rename symbol";
      }
      {
        mode = "n";
        key = "<leader>ca";
        lspBufAction = "code_action";
        options.desc = "Code action";
      }
      {
        mode = "n";
        key = "<leader>wd";
        lspBufAction = "workspace_diagnostics";
        options.desc = "Workspace diagnostics";
      }
    ];
  };

  keymaps = [
    {
      mode = "n";
      key = "[d";
      action.__raw = "function() vim.diagnostic.jump({ count = -1, float = true }) end";
      options.desc = "Prev diagnostic";
    }
    {
      mode = "n";
      key = "]d";
      action.__raw = "function() vim.diagnostic.jump({ count = 1, float = true }) end";
      options.desc = "Next diagnostic";
    }
    {
      mode = "n";
      key = "<leader>lr";
      action.__raw = ''
        function()
          local bufnr = vim.api.nvim_get_current_buf()
          local ft = vim.bo[bufnr].filetype
          for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
            client:stop()
          end
          vim.defer_fn(function()
            vim.api.nvim_exec_autocmds("FileType", { pattern = ft })
          end, 500)
        end
      '';
      options.desc = "Restart LSP";
    }
  ];
}
