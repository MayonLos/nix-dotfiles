{
  plugins.mini = {
    enable = true;

    # Load the shared mini.nvim runtime only when one of its mappings is used.
    # mini.align and mini.splitjoin install their normal/visual mappings during
    # setup, after lz.n has consumed the first keypress.
    lazyLoad = {
      enable = true;
      settings.keys = [
        {
          __unkeyed-1 = "ga";
          mode = [
            "n"
            "x"
          ];
          desc = "Align text";
        }
        {
          __unkeyed-1 = "gA";
          mode = [
            "n"
            "x"
          ];
          desc = "Align text with preview";
        }
        {
          __unkeyed-1 = "gS";
          mode = [
            "n"
            "x"
          ];
          desc = "Toggle split/join";
        }
      ];
    };

    modules = {
      align = { };
      splitjoin = { };
    };
  };
}
