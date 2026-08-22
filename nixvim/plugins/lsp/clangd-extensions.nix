{
  plugins.clangd-extensions = {
    enable = true;

    lazyLoad.settings.ft = [
      "c"
      "cpp"
      "objc"
      "objcpp"
      "cuda"
    ];
  };

  keymaps = [
    {
      mode = "n";
      key = "<leader>la";
      action = "<cmd>ClangdAST<cr>";
      options.desc = "clangd: AST";
    }
    {
      mode = "n";
      key = "<leader>lt";
      action = "<cmd>ClangdTypeHierarchy<cr>";
      options.desc = "clangd: Type hierarchy";
    }
    {
      mode = "n";
      key = "<leader>li";
      action = "<cmd>ClangdSymbolInfo<cr>";
      options.desc = "clangd: Symbol info";
    }
    {
      mode = "n";
      key = "<leader>lh";
      action.__raw = ''
        function()
          local client = vim.lsp.get_clients({ bufnr = 0, name = "clangd" })[1]
          if not client then
            vim.notify("clangd not attached", vim.log.levels.WARN)
            return
          end
          local params = vim.lsp.util.make_text_document_params(0)
          client:request("textDocument/switchSourceHeader", params, function(err, result)
            if err or not result then
              vim.notify("clangd: no matching source/header", vim.log.levels.WARN)
              return
            end
            vim.cmd.edit(vim.uri_to_fname(result))
          end, 0)
        end
      '';
      options.desc = "Switch source/header";
    }
  ];
}
