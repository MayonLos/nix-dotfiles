_: {
  extraConfigLuaPost = ''
    local function apply_custom_hl()
      local function get(name)
        return vim.api.nvim_get_hl(0, { name = name, link = false })
      end
      local normal  = get("Normal")
      local comment = get("Comment")
      local visual  = get("Visual")
      local folded  = get("Folded")
      local float   = get("NormalFloat")
      local accent  = get("Function")
      local match   = get("MatchParen")

      -- Opaque surfaces keep CJK prose legible under floats in light and dark
      -- styles alike; only the severity icon needs a saturated colour.
      vim.api.nvim_set_hl(0, "NormalFloat", { fg = normal.fg, bg = float.bg or normal.bg })
      vim.api.nvim_set_hl(0, "FloatBorder", { fg = comment.fg, bg = float.bg or normal.bg })
      vim.api.nvim_set_hl(0, "FloatTitle", { fg = accent.fg, bg = float.bg or normal.bg, bold = true })
      vim.api.nvim_set_hl(0, "MultiCursor", { fg = normal.fg, bg = visual.bg, underline = true })
      vim.api.nvim_set_hl(0, "MultiCursorMain", { fg = normal.bg, bg = accent.fg, bold = true })
      -- Retain the scheme's contrast while adding the pairing cue.
      match.bold, match.underline = true, true
      vim.api.nvim_set_hl(0, "MatchParen", match)
      vim.api.nvim_set_hl(0, "TabLine", { bg = folded.bg, fg = comment.fg })
      vim.api.nvim_set_hl(0, "TabLineSel", { bg = visual.bg, fg = normal.fg, bold = true })

      local links = {
        DapStoppedLine = "CursorLine",
        TreesitterContext = "NormalFloat",
        TreesitterContextSeparator = "FloatBorder",
        SoftFloatBorder = "FloatBorder",
        WhichKeyNormal = "NormalFloat",
        WhichKeyBorder = "FloatBorder",
        TabLineFill = "StatusLine",
        BlinkCmpMenu = "NormalFloat",
        BlinkCmpMenuBorder = "FloatBorder",
        BlinkCmpMenuSelection = "PmenuSel",
        BlinkCmpDoc = "NormalFloat",
        BlinkCmpDocBorder = "FloatBorder",
        BlinkCmpSignatureHelp = "NormalFloat",
        BlinkCmpSignatureHelpBorder = "FloatBorder",
        NoiceCmdlinePopup = "NormalFloat",
        NoiceCmdlinePopupBorder = "FloatBorder",
        NoiceCmdlinePopupTitle = "FloatTitle",
        NoicePopup = "NormalFloat",
        NoicePopupBorder = "FloatBorder",
        NoiceConfirm = "NormalFloat",
        NoiceConfirmBorder = "FloatBorder",
        SnacksInputNormal = "NormalFloat",
        SnacksInputBorder = "FloatBorder",
        SnacksIndent = "NonText",
        SnacksIndentScope = "Comment",
        TroubleNormal = "Normal",
        TroubleNormalNC = "Normal",
      }
      for _, level in ipairs({ "Error", "Warn", "Info", "Debug", "Trace" }) do
        links["SnacksNotifier" .. level] = "NormalFloat"
        links["SnacksNotifierBorder" .. level] = "FloatBorder"
      end
      -- noice names its cmdline border group per cmdline kind, so the set is
      -- only known once noice has drawn one. DevIcon* is deliberately left
      -- alone -- those are file-type brand colours, see icons.nix.
      for name in pairs(vim.api.nvim_get_hl(0, {})) do
        if name:match("^NoiceCmdlinePopupBorder") then links[name] = "FloatBorder" end
      end
      for name, target in pairs(links) do
        vim.api.nvim_set_hl(0, name, { link = target })
      end
    end

    apply_custom_hl()
    vim.api.nvim_create_autocmd("ColorScheme", {
      group = vim.api.nvim_create_augroup("CustomHighlights", { clear = true }),
      callback = apply_custom_hl,
    })
  '';
}
