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
