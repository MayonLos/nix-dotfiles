{
  plugins.undotree = {
    enable = true;
    settings = {
      SetFocusWhenToggle = true;
      HighlightChangedText = true;
    };
    lazyLoad = {
      enable = true;
      settings.keys = [
        {
          __unkeyed-1 = "<leader>uu";
          __unkeyed-2 = "<cmd>UndotreeToggle<cr>";
          mode = [ "n" ];
          desc = "Toggle Undotree";
        }
      ];
    };
  };
}
