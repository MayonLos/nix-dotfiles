{
  plugins.lint = {
    enable = true;

    lazyLoad.settings.event = [
      "FileType"
      "BufWritePost"
      "InsertLeave"
    ];
    lintersByFt = {
      python = [ "ruff" ];
      lua = [ "luacheck" ];
      # shellcheck is in toolchain.nix and was reachable from neither editor
      # until this line: nvim linted nothing for sh/bash, and Emacs' built-in
      # flymake backend shells out to `sh -n`, not to shellcheck.
      sh = [ "shellcheck" ];
      bash = [ "shellcheck" ];
    };
    # NOT BufReadPost. It fires before filetype detection, so `try_lint` looked
    # up `linters_by_ft[""]`, missed, and produced nothing -- a file opened
    # cold had zero diagnostics until its first `:w`. Measured: 0 diagnostics
    # after open, 2 after write, on the same lua buffer. FileType is the
    # earliest event at which the filetype is actually known; InsertLeave is
    # what makes the marks track editing rather than only saving.
    autoCmd.event = [
      "FileType"
      "BufWritePost"
      "InsertLeave"
    ];
  };
}
