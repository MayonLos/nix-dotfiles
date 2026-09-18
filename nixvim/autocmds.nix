{
  autoGroups = {
    RestoreCursorPosition = {
      clear = true;
    };
  };

  autoCmd = [
    {
      event = "BufReadPost";
      group = "RestoreCursorPosition";
      callback.__raw = ''
        function(args)
          local mark = vim.api.nvim_buf_get_mark(args.buf, '"')
          local line_count = vim.api.nvim_buf_line_count(args.buf)
          if mark[1] > 0 and mark[1] <= line_count then
            pcall(vim.api.nvim_win_set_cursor, 0, mark)
          end
        end
      '';
    }
    # Opening a PDF in nvim used to load the raw binary and fill the screen with
    # mojibake. Neovim cannot render one and never will, so hand it to the
    # desktop handler -- xdg-open resolves application/pdf to zathura via
    # modules/home/base/xdg.nix -- and leave no buffer behind.
    #
    # BufReadCmd rather than BufReadPre: it *replaces* the read, so the bytes
    # are never loaded in the first place. The delete is scheduled because the
    # buffer cannot be wiped from inside the autocommand that is reading it.
    {
      event = "BufReadCmd";
      pattern = [
        "*.pdf"
        "*.PDF"
      ];
      callback.__raw = ''
        function(args)
          local file = vim.fn.fnamemodify(args.file, ":p")
          local proc, err = vim.ui.open(file)
          if not proc then
            vim.notify("Cannot open " .. file .. ": " .. tostring(err), vim.log.levels.ERROR)
            return
          end
          vim.notify(vim.fn.fnamemodify(file, ":t"), vim.log.levels.INFO, { title = "Opened externally" })
          vim.schedule(function()
            if vim.api.nvim_buf_is_valid(args.buf) then
              vim.api.nvim_buf_delete(args.buf, { force = true })
            end
          end)
        end
      '';
    }
    {
      event = "TextYankPost";
      callback.__raw = ''
        function()
          vim.hl.on_yank({ timeout = 200 })
        end
      '';
    }
  ];
}
