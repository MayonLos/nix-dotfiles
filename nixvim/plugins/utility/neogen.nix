{
  plugins.neogen = {
    enable = true;
    settings = {
      snippet_engine = "luasnip";
      languages = {
        python.template.annotation_convention = "google_docstrings";
      };
    };
    lazyLoad = {
      enable = true;
      settings = {
        cmd = [ "Neogen" ];
        keys = [
          {
            __unkeyed-1 = "<leader>nd";
            __unkeyed-2 = "<cmd>Neogen<cr>";
            desc = "Generate doc (nearest)";
          }
          {
            __unkeyed-1 = "<leader>nf";
            __unkeyed-2 = "<cmd>Neogen func<cr>";
            desc = "Generate function doc";
          }
          {
            __unkeyed-1 = "<leader>nc";
            __unkeyed-2 = "<cmd>Neogen class<cr>";
            desc = "Generate class doc";
          }
          {
            __unkeyed-1 = "<leader>nt";
            __unkeyed-2 = "<cmd>Neogen type<cr>";
            desc = "Generate type doc";
          }
        ];
      };
    };
  };
}
