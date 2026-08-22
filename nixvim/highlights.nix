{
  highlight = {
    MultiCursor = {
      bg = "#3b4252";
      fg = "#81a1c1";
      underline = true;
    };
    MultiCursorMain = {
      bg = "#4c566a";
      fg = "#eceff4";
      bold = true;
    };
    MatchParen = {
      bold = true;
      underline = true;
    };
    DapStoppedLine = {
      link = "CursorLine";
    };
    TreesitterContextSeparator = {
      fg = "#3b4261";
    };
  };

  extraConfigLuaPost = ''
    local function apply_custom_hl()
      local normal   = vim.api.nvim_get_hl(0, { name = "Normal" })
      local hl_float = vim.api.nvim_get_hl(0, { name = "NormalFloat" })
      local comment  = vim.api.nvim_get_hl(0, { name = "Comment" })
      local visual   = vim.api.nvim_get_hl(0, { name = "Visual" })
      local folded   = vim.api.nvim_get_hl(0, { name = "Folded" })

      vim.api.nvim_set_hl(0, "NormalFloat",       { fg = hl_float.fg, bg = "NONE" })
      vim.api.nvim_set_hl(0, "FloatBorder",       { fg = normal.fg,   bg = "NONE", bold = true })
      vim.api.nvim_set_hl(0, "TreesitterContext", { link = "NormalFloat" })

      vim.api.nvim_set_hl(0, "SoftFloatBorder", { fg = comment.fg, bg = "NONE" })

      vim.api.nvim_set_hl(0, "WhichKeyNormal", { link = "Normal" })
      vim.api.nvim_set_hl(0, "WhichKeyBorder", { link = "SoftFloatBorder" })

      vim.api.nvim_set_hl(0, "TabLine",    { bg = folded.bg, fg = comment.fg })
      vim.api.nvim_set_hl(0, "TabLineSel", { bg = visual.bg, fg = normal.fg, bold = true })
    end

    apply_custom_hl()
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = vim.api.nvim_create_augroup("CustomHighlights", { clear = true }),
      callback = apply_custom_hl,
    })
  '';
}
