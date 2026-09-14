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
      local accent  = get("Function")
      local match   = get("MatchParen")

      -- Transparent on purpose, and not only as a look: TreesitterContext links
      -- to NormalFloat (see the link table below), so the context lines pinned
      -- at the top of a window are painted with these groups. Given them a
      -- surface of their own and the top of every code window grows a slab that
      -- does not belong to the buffer it is describing. An opaque variant was
      -- tried and reverted for exactly that.
      vim.api.nvim_set_hl(0, "NormalFloat", { fg = normal.fg, bg = "NONE" })
      vim.api.nvim_set_hl(0, "FloatBorder", { fg = comment.fg, bg = "NONE" })
      vim.api.nvim_set_hl(0, "FloatTitle", { fg = accent.fg, bg = "NONE", bold = true })
      -- multicursor.nvim's group names, not smoka7's MultiCursor/MultiCursorMain
      -- (editing/multicursors.nix). A disabled cursor has to stay visible but
      -- read as inert, so it borrows the comment colour rather than the accent.
      vim.api.nvim_set_hl(0, "MultiCursorCursor", { fg = normal.bg, bg = accent.fg, bold = true })
      vim.api.nvim_set_hl(0, "MultiCursorDisabledCursor", { fg = normal.bg, bg = comment.fg })
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
        -- Not NormalFloat: which-key and the completion menu are the two
        -- surfaces that sit *on top of* code you are still reading, so they
        -- have to occlude it. Everything else in this table is a panel you
        -- look at instead of the buffer, and those follow NormalFloat.
        WhichKeyNormal = "Normal",
        WhichKeyBorder = "FloatBorder",
        BlinkCmpMenu = "Pmenu",
        BlinkCmpMenuBorder = "FloatBorder",
        BlinkCmpMenuSelection = "PmenuSel",
        TabLineFill = "StatusLine",
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
        MultiCursorVisual = "Visual",
        MultiCursorSign = "SignColumn",
        MultiCursorMatchPreview = "Search",
        MultiCursorDisabledVisual = "Folded",
        MultiCursorDisabledSign = "SignColumn",
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
