{
  plugins.grug-far = {
    enable = true;
    lazyLoad = {
      enable = true;
      settings.keys = [
        {
          __unkeyed-1 = "<leader>sr";
          __unkeyed-2 = "<cmd>GrugFar<cr>";
          mode = [
            "n"
            "v"
          ];
          desc = "Search and Replace";
        }
      ];
    };
    settings = {
      headerMaxWidth = 80;
      border = "rounded";
    };
  };
}
