{
  cpp = {
    id = "cpp";
    neovim = {
      servers.clangd = {
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
      formatters = {
        c = [ "clang-format" ];
        cpp = [ "clang-format" ];
      };
      linters = { };
    };
  };
  docker = {
    id = "docker";
    neovim = {
      servers.dockerls = {
        cmd = [
          "docker-langserver"
          "--stdio"
        ];
        filetypes = [ "dockerfile" ];
        root_markers = [ ".git" ];
      };
      formatters = { };
      linters = { };
    };
  };
  nix = {
    id = "nix";
    neovim = {
      servers.nixd = {
        cmd = [ "nixd" ];
        filetypes = [ "nix" ];
        root_markers = [
          "flake.nix"
          ".git"
        ];
      };
      formatters.nix = [ "nixfmt" ];
      linters = { };
    };
  };
  lua = {
    id = "lua";
    neovim = {
      servers.lua_ls = {
        cmd = [ "lua-language-server" ];
        filetypes = [ "lua" ];
        root_markers = [
          ".luarc.json"
          ".luarc.jsonc"
          ".stylua.toml"
          ".git"
        ];
      };
      formatters.lua = [ "stylua" ];
      linters.lua = [ "luacheck" ];
    };
  };
  python = {
    id = "python";
    neovim = {
      servers.pyright = {
        cmd = [
          "pyright-langserver"
          "--stdio"
        ];
        filetypes = [ "python" ];
        root_markers = [
          "pyproject.toml"
          "pyrightconfig.json"
          "uv.lock"
          "setup.py"
          "setup.cfg"
          "requirements.txt"
          ".git"
        ];
      };
      formatters.python = [
        "ruff_organize_imports"
        "ruff_format"
      ];
      linters.python = [ "ruff" ];
    };
  };
  java = {
    id = "java";
    neovim = {
      servers.jdtls = {
        cmd = [ "jdtls" ];
        filetypes = [ "java" ];
        root_markers = [
          "pom.xml"
          "build.gradle"
          "settings.gradle"
          ".git"
        ];
      };
      formatters.java = [ "google-java-format" ];
      linters = { };
    };
  };
  shell = {
    id = "shell";
    neovim = {
      servers.bashls = {
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
      formatters = {
        bash = [ "shfmt" ];
        sh = [ "shfmt" ];
      };
      linters = {
        bash = [ "shellcheck" ];
        sh = [ "shellcheck" ];
      };
    };
  };
  latex = {
    id = "latex";
    neovim = {
      servers.texlab = {
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
      };
      formatters.tex = [ "latexindent" ];
      linters = { };
    };
  };
  markdown = {
    id = "markdown";
    neovim = {
      servers.marksman = {
        cmd = [
          "marksman"
          "server"
        ];
        filetypes = [ "markdown" ];
        root_markers = [
          ".marksman.toml"
          ".git"
        ];
      };
      formatters = { };
      linters = { };
    };
  };
  matlab = {
    id = "matlab";
    neovim = {
      servers.matlab_ls = {
        cmd = [ "matlab-ls" ];
        filetypes = [ "matlab" ];
        root_markers = [ ".git" ];
      };
      formatters.matlab = {
        lsp_format = "fallback";
      };
      linters = { };
    };
  };
  cmake = {
    id = "cmake";
    neovim = {
      servers.cmake = {
        cmd = [ "cmake-language-server" ];
        filetypes = [ "cmake" ];
        root_markers = [
          "CMakeLists.txt"
          "CMakePresets.json"
          ".git"
        ];
      };
      formatters = { };
      linters = { };
    };
  };
  web = {
    id = "web";
    neovim = {
      servers = {
        html = {
          cmd = [
            "vscode-html-language-server"
            "--stdio"
          ];
          filetypes = [
            "html"
            "templ"
          ];
          root_markers = [
            "package.json"
            ".git"
          ];
        };
        cssls = {
          cmd = [
            "vscode-css-language-server"
            "--stdio"
          ];
          filetypes = [
            "css"
            "scss"
            "less"
          ];
          root_markers = [
            "package.json"
            ".git"
          ];
        };
        jsonls = {
          cmd = [
            "vscode-json-language-server"
            "--stdio"
          ];
          filetypes = [
            "json"
            "jsonc"
          ];
          root_markers = [
            "package.json"
            ".git"
          ];
        };
        ts_ls = {
          cmd = [
            "typescript-language-server"
            "--stdio"
          ];
          filetypes = [
            "javascript"
            "javascriptreact"
            "typescript"
            "typescriptreact"
          ];
          root_markers = [
            "tsconfig.json"
            "jsconfig.json"
            "package.json"
            ".git"
          ];
        };
      };
      formatters = { };
      linters = { };
    };
  };
  yaml = {
    id = "yaml";
    neovim = {
      servers.yamlls = {
        cmd = [
          "yaml-language-server"
          "--stdio"
        ];
        filetypes = [ "yaml" ];
        root_markers = [ ".git" ];
      };
      formatters = { };
      linters = { };
    };
  };
}
