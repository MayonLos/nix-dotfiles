local M = {}

-- One Dark Darker palette, from navarasu/onedark.nvim (MIT).
-- https://github.com/navarasu/onedark.nvim/blob/master/lua/onedark/palette.lua
-- The highlight definitions below belong to this configuration.
local c = require("mayon.generated").palette

function M.apply()
	vim.cmd.highlight("clear")
	if vim.fn.exists("syntax_on") == 1 then
		vim.cmd.syntax("reset")
	end
	vim.o.background = "dark"
	vim.g.colors_name = c.name
	local groups = {
		Normal = { fg = c.fg, bg = c.bg },
		NormalNC = { fg = c.fg, bg = c.bg },
		NormalFloat = { fg = c.fg, bg = c.deep },
		FloatBorder = { fg = c.border, bg = c.deep },
		FloatTitle = { fg = c.blue, bg = c.deep, bold = true },
		WinSeparator = { fg = c.deep, bg = c.bg },
		SignColumn = { bg = c.bg },
		LineNr = { fg = c.border },
		CursorLineNr = { fg = c.yellow, bold = true },
		CursorLine = { bg = c.surface },
		ColorColumn = { bg = c.surface },
		Cursor = { fg = c.bg, bg = c.fg },
		TermCursor = { fg = c.bg, bg = c.blue },
		EndOfBuffer = { fg = c.bg },
		NonText = { fg = c.border },
		Whitespace = { fg = c.border },
		Visual = { bg = c.selection },
		Search = { fg = c.bg, bg = c.yellow },
		IncSearch = { fg = c.bg, bg = c.orange },
		CurSearch = { fg = c.bg, bg = c.orange, bold = true },
		MatchParen = { fg = c.yellow, bg = c.selection, bold = true, underline = true },
		Pmenu = { fg = c.fg, bg = c.deep },
		PmenuSel = { fg = c.fg, bg = c.selection, bold = true },
		PmenuSbar = { bg = c.surface },
		PmenuThumb = { bg = c.border },
		StatusLine = { fg = c.fg, bg = c.deep },
		StatusLineNC = { fg = c.muted, bg = c.deep },
		TabLine = { fg = c.muted, bg = c.deep },
		TabLineSel = { fg = c.fg, bg = c.selection, bold = true },
		TabLineFill = { bg = c.deep },
		Folded = { fg = c.muted, bg = c.surface },
		FoldColumn = { fg = c.border, bg = c.bg },
		Comment = { fg = c.muted, italic = true },
		Constant = { fg = c.orange },
		String = { fg = c.green },
		Character = { fg = c.green },
		Number = { fg = c.orange },
		Boolean = { fg = c.orange },
		Float = { fg = c.orange },
		Identifier = { fg = c.red },
		Function = { fg = c.blue },
		Statement = { fg = c.purple },
		Operator = { fg = c.cyan },
		Keyword = { fg = c.purple },
		PreProc = { fg = c.yellow },
		Type = { fg = c.yellow },
		Special = { fg = c.cyan },
		Delimiter = { fg = c.fg },
		Underlined = { fg = c.blue, underline = true },
		Error = { fg = c.red },
		Todo = { fg = c.yellow, bold = true },
		Title = { fg = c.blue, bold = true },
		Directory = { fg = c.blue },
		Question = { fg = c.green },
		MoreMsg = { fg = c.green },
		ModeMsg = { fg = c.blue },
		WarningMsg = { fg = c.yellow },
		ErrorMsg = { fg = c.red },
		DiffAdd = { bg = "#272e23" },
		DiffDelete = { fg = c.red, bg = "#2d2223" },
		DiffChange = { bg = "#172a3a" },
		DiffText = { bg = "#274964" },
		Added = { fg = c.green },
		Changed = { fg = c.blue },
		Removed = { fg = c.red },
		DiagnosticError = { fg = c.red },
		DiagnosticWarn = { fg = c.yellow },
		DiagnosticInfo = { fg = c.blue },
		DiagnosticHint = { fg = c.cyan },
		DiagnosticOk = { fg = c.green },
		DiagnosticUnnecessary = { fg = c.muted },
		DiagnosticDeprecated = { strikethrough = true },
		LspInlayHint = { fg = c.muted, bg = c.surface },
		LspReferenceText = { bg = c.selection },
		LspReferenceRead = { bg = c.selection },
		LspReferenceWrite = { bg = c.selection, underline = true },
		TreesitterContext = { bg = c.bg },
		TreesitterContextSeparator = { fg = c.border, bg = c.bg },
		TreesitterContextLineNumber = { fg = c.muted, bg = c.bg },
		MultiCursorCursor = { fg = c.bg, bg = c.blue, bold = true },
		MultiCursorDisabledCursor = { fg = c.bg, bg = c.muted },
		GitSignsAdd = { fg = c.green },
		GitSignsChange = { fg = c.blue },
		GitSignsDelete = { fg = c.red },
		WhichKey = { fg = c.blue },
		WhichKeyGroup = { fg = c.purple },
		WhichKeyDesc = { fg = c.fg },
		WhichKeySeparator = { fg = c.muted },
		BlinkCmpLabelMatch = { fg = c.blue, bold = true },
		BlinkCmpSource = { fg = c.muted },
		FzfLuaSurface = { fg = c.fg, bg = c.bg },
		FzfLuaSurfaceBorder = { fg = c.border, bg = c.bg },
		FzfLuaSurfaceTitle = { fg = c.blue, bg = c.bg, bold = true },
		["@variable"] = { fg = c.fg },
		["@variable.builtin"] = { fg = c.red },
		["@variable.parameter"] = { fg = c.orange },
		["@markup.heading"] = { fg = c.blue, bold = true },
		["@markup.strong"] = { bold = true },
		["@markup.italic"] = { italic = true },
		["@markup.raw"] = { fg = c.green },
		["@markup.link.url"] = { fg = c.cyan, underline = true },
		["@markup.list"] = { fg = c.red },
		["@tag"] = { fg = c.red },
		["@tag.attribute"] = { fg = c.yellow },
		["@tag.delimiter"] = { fg = c.muted },
	}
	local links = {
		SoftFloatBorder = "FloatBorder",
		WhichKeyNormal = "NormalFloat",
		WhichKeyBorder = "FloatBorder",
		BlinkCmpMenu = "Pmenu",
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
		MultiCursorVisual = "Visual",
		MultiCursorSign = "SignColumn",
		MultiCursorMatchPreview = "Search",
		MultiCursorDisabledVisual = "Folded",
		MultiCursorDisabledSign = "SignColumn",
		["@constant"] = "Constant",
		["@string"] = "String",
		["@string.escape"] = "Special",
		["@string.regexp"] = "Special",
		["@number"] = "Number",
		["@boolean"] = "Boolean",
		["@function"] = "Function",
		["@function.builtin"] = "Special",
		["@function.call"] = "Function",
		["@function.method"] = "Function",
		["@constructor"] = "Type",
		["@keyword"] = "Keyword",
		["@operator"] = "Operator",
		["@type"] = "Type",
		["@type.builtin"] = "Type",
		["@module"] = "Type",
		["@property"] = "Identifier",
		["@attribute"] = "PreProc",
		["@comment"] = "Comment",
		["@punctuation.delimiter"] = "Delimiter",
		["@punctuation.bracket"] = "Delimiter",
		["@punctuation.special"] = "Special",
		["@lsp.type.class"] = "Type",
		["@lsp.type.enum"] = "Type",
		["@lsp.type.interface"] = "Type",
		["@lsp.type.namespace"] = "Type",
		["@lsp.type.parameter"] = "@variable.parameter",
		["@lsp.type.property"] = "@property",
		["@lsp.type.variable"] = "@variable",
	}
	for _, kind in ipairs({ "Error", "Warn", "Info", "Hint", "Ok" }) do
		local diagnostic = groups["Diagnostic" .. kind]
		groups["DiagnosticUnderline" .. kind] = { sp = diagnostic.fg, undercurl = true }
	end
	for _, name in ipairs({
		"FzfLuaBorder",
		"FzfLuaPreviewBorder",
		"FzfLuaFzfBorder",
		"FzfLuaFzfSeparator",
		"FzfLuaScrollBorderEmpty",
		"FzfLuaScrollBorderFull",
	}) do
		links[name] = "FzfLuaSurfaceBorder"
	end
	for _, name in ipairs({ "FzfLuaNormal", "FzfLuaPreviewNormal", "FzfLuaFzfNormal", "FzfLuaFzfGutter" }) do
		links[name] = "FzfLuaSurface"
	end
	links.FzfLuaTitle, links.FzfLuaPreviewTitle = "FzfLuaSurfaceTitle", "FzfLuaSurfaceTitle"
	for name, value in pairs(groups) do
		vim.api.nvim_set_hl(0, name, value)
	end
	for name, target in pairs(links) do
		vim.api.nvim_set_hl(0, name, { link = target })
	end
	local terminal = require("mayon.generated").ansi
	for i, color in ipairs(terminal) do
		vim.g["terminal_color_" .. (i - 1)] = color
	end
end

return M
