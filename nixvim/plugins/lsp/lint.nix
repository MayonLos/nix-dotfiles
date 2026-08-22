{
  plugins.lint = {
    enable = true;

    lazyLoad.settings.event = [
      "BufReadPost"
      "BufWritePost"
    ];
    lintersByFt = {
      python = [ "ruff" ];
      lua = [ "luacheck" ];
    };
    autoCmd.event = [
      "BufReadPost"
      "BufWritePost"
    ];
  };
}
