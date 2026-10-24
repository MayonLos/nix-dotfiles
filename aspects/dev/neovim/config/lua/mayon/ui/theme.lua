-- One Dark owns syntax/plugin highlights; this adapter restores the
-- editor surfaces without maintaining a second syntax theme.
local M = {}
local configured = false

local function blend(foreground, background, alpha)
	local function channel(hex, offset)
		return tonumber(hex:sub(offset, offset + 1), 16)
	end
	local result = { "#" }
	for offset = 2, 6, 2 do
		local value = math.floor(channel(foreground, offset) * alpha + channel(background, offset) * (1 - alpha) + 0.5)
		result[#result + 1] = string.format("%02x", value)
	end
	return table.concat(result)
end

M.blend = blend

local function overrides()
	local function get(name)
		return vim.api.nvim_get_hl(0, { name = name, link = false })
	end
	local c = require("mayon.generated").palette
	local function set(name, values)
		vim.api.nvim_set_hl(0, name, values)
	end
	set("Normal", { fg = c.brightFg, bg = c.deep })
	set("NormalNC", { fg = c.brightFg, bg = c.deep })
	set("Visual", { fg = c.brightFg, bg = c.selection })
	set("VisualNOS", { fg = c.brightFg, bg = c.selection })
	set("LineNr", { fg = c.fg, bg = c.deep })
	set("CursorLineNr", { fg = c.brightFg, bg = c.deep, bold = true })
	set("CursorLine", { bg = c.deep })
	set("CursorLineSign", { bg = c.deep })
	set("SignColumn", { bg = c.deep })
	set("WinSeparator", { fg = c.border, bg = c.deep })
	set("StatusLine", { fg = c.fg, bg = c.deep })
	set("StatusLineNC", { fg = c.fg, bg = c.deep })
	set("MayonProject", { fg = c.blue, bg = c.surface, bold = true })
	set("MayonPosition", { fg = c.brightFg, bg = c.surface, bold = true })
	set("MayonTabAccent", { fg = c.blue, bg = c.selection })
	set("MayonTabVisible", { fg = c.fg, bg = c.deep, bold = true })
	set("MayonMuted", { fg = c.muted })
	set("MayonDashboardBlue", { fg = c.blue, bold = true })
	set("MayonDashboardMix", { fg = c.cyan, bold = true })
	set("MayonDashboardCyan", { fg = c.cyan, bold = true })
	set("MayonDashboardMuted", { fg = c.muted })
	set("MayonModeNormal", { fg = c.bg, bg = c.blue, bold = true })
	set("MayonModeInsert", { fg = c.bg, bg = c.green, bold = true })
	set("MayonModeVisual", { fg = c.bg, bg = c.yellow, bold = true })
	set("MayonModeReplace", { fg = c.bg, bg = c.red, bold = true })
	set("MayonModeCommand", { fg = c.bg, bg = c.orange, bold = true })
	set("MayonStatusGit", { fg = c.cyan })
	set("MayonStatusAdded", { fg = c.green })
	set("MayonStatusChanged", { fg = c.orange })
	set("MayonStatusRemoved", { fg = c.red })
	set("DiagnosticError", { fg = c.red })
	set("DiagnosticWarn", { fg = c.yellow })
	set("DiagnosticInfo", { fg = c.blue })
	set("DiagnosticHint", { fg = c.cyan })
	set("DiagnosticOk", { fg = c.green })
	set("DiagnosticSignError", { fg = c.red })
	set("DiagnosticSignWarn", { fg = c.yellow })
	set("DiagnosticSignInfo", { fg = c.blue })
	set("DiagnosticSignHint", { fg = c.cyan })
	set("DiagnosticSignOk", { fg = c.green })
	vim.api.nvim_set_hl(0, "NormalFloat", { fg = c.brightFg, bg = c.bg })
	vim.api.nvim_set_hl(0, "FloatBorder", { fg = c.border, bg = c.bg })
	vim.api.nvim_set_hl(0, "FloatTitle", { fg = c.blue, bg = c.bg, bold = true })
	vim.api.nvim_set_hl(0, "MultiCursorCursor", { fg = c.bg, bg = c.cyan, bold = true })
	vim.api.nvim_set_hl(0, "MultiCursorDisabledCursor", { fg = c.bg, bg = c.muted })
	local match = get("MatchParen")
	match.bold, match.underline = true, true
	vim.api.nvim_set_hl(0, "MatchParen", match)
	set("TabLine", { bg = c.deep, fg = c.fg })
	set("TabLineSel", { bg = c.selection, fg = c.blue, bold = true, underline = true, sp = c.blue })
	set("TabLineFill", { bg = c.deep, fg = c.fg })
	set("TreesitterContext", { bg = c.surface })
	set("TreesitterContextLineNumber", { bg = c.surface, fg = c.fg })
	set("TreesitterContextSeparator", { fg = c.border, bg = c.surface })
	set("Pmenu", { fg = c.brightFg, bg = c.bg })
	set("PmenuSel", { fg = c.brightFg, bg = c.selection, bold = true })
	set("PmenuKind", { fg = c.cyan, bg = c.bg })
	set("PmenuKindSel", { fg = c.blue, bg = c.selection })
	set("PmenuExtra", { fg = c.fg, bg = c.bg })
	set("PmenuExtraSel", { fg = c.fg, bg = c.selection })
	set("PmenuBorder", { fg = c.border, bg = c.bg })
	set("PmenuSbar", { bg = c.surface })
	set("PmenuThumb", { bg = c.border })
	set("PmenuMatch", { fg = c.cyan, bg = c.bg, bold = true })
	set("PmenuMatchSel", { fg = c.blue, bg = c.selection, bold = true })
	set("SnippetTabstopActive", { bg = c.selection, underline = true, sp = c.cyan })
	set("LspInlineCompletion", { fg = c.muted, italic = true })
	for level, color in ipairs({ c.blue, c.cyan, c.fg, c.fg, c.fg, c.fg }) do
		set("RenderMarkdownH" .. level, { fg = color, bold = true })
		-- Render-markdown owns the icon/background; Tree-sitter owns heading text.
		set("@markup.heading." .. level .. ".markdown", { link = "RenderMarkdownH" .. level })
		set("markdownH" .. level, { link = "RenderMarkdownH" .. level })
		set("RenderMarkdownH" .. level .. "Bg", { bg = c.bg })
	end
	set("RenderMarkdownCode", { fg = c.fg, bg = c.surface })
	set("RenderMarkdownCodeInline", { fg = c.cyan, bg = c.surface })
	set("SnacksImageMath", { fg = c.brightFg })
	set("RenderMarkdownCodeBorder", { fg = c.border, bg = c.bg })
	set("RenderMarkdownTableHead", { fg = c.cyan, bold = true })
	set("@markup.heading.markdown", { link = "RenderMarkdownTableHead" })
	set("RenderMarkdownTableRow", { fg = c.border })
	set("RenderMarkdownTableFill", { bg = c.bg })
	set("RenderMarkdownBullet", { fg = c.cyan })
	set("RenderMarkdownQuote", { fg = c.cyan })
	set("RenderMarkdownDash", { fg = c.border })
	for name, color in pairs({
		RainbowDelimiterRed = c.red,
		RainbowDelimiterYellow = c.yellow,
		RainbowDelimiterBlue = c.blue,
		RainbowDelimiterOrange = c.orange,
		RainbowDelimiterGreen = c.green,
		RainbowDelimiterViolet = c.purple,
		RainbowDelimiterCyan = c.cyan,
	}) do
		vim.api.nvim_set_hl(0, name, { fg = color })
	end
	local todo_colors = {
		FIX = c.red,
		TODO = c.blue,
		HACK = c.orange,
		WARN = c.orange,
		PERF = c.purple,
		NOTE = c.cyan,
		TEST = c.green,
	}
	for todo, color in pairs(todo_colors) do
		vim.api.nvim_set_hl(0, "TodoFg" .. todo, { fg = color, bold = true })
		vim.api.nvim_set_hl(0, "TodoBg" .. todo, { fg = c.bg, bg = color, bold = true })
		vim.api.nvim_set_hl(0, "TodoSign" .. todo, { fg = color })
	end
	set("OilDir", { fg = c.blue, bold = true })
	set("OilDirIcon", { fg = c.cyan })
	set("OilDirHidden", { fg = c.muted, bold = true })
	set("OilFile", { fg = c.fg })
	set("OilFileHidden", { fg = c.muted })
	set("OilSocket", { fg = c.purple })
	set("OilSocketHidden", { fg = c.muted })
	set("OilLink", { fg = c.cyan, underline = true })
	set("OilOrphanLink", { fg = c.red, underline = true })
	set("OilLinkHidden", { fg = c.muted, underline = true })
	set("OilOrphanLinkHidden", { fg = c.red, underline = true })
	set("OilLinkTarget", { fg = c.muted })
	set("OilOrphanLinkTarget", { fg = c.red })
	set("OilLinkTargetHidden", { fg = c.muted })
	set("OilOrphanLinkTargetHidden", { fg = c.red })
	set("OilCreate", { fg = c.green })
	set("OilDelete", { fg = c.red, strikethrough = true })
	set("OilMove", { fg = c.orange })
	set("OilCopy", { fg = c.green })
	set("OilChange", { fg = c.orange })
	set("OilRestore", { fg = c.green })
	set("OilPurge", { fg = c.red, bold = true })
	set("OilTrash", { fg = c.red })
	set("OilTrashSourcePath", { fg = c.muted, italic = true })
	set("OilHidden", { fg = c.muted })
	set("InclineNormal", { fg = c.fg, bg = c.surface })
	set("InclineNormalNC", { fg = c.muted, bg = c.bg })
	set("SatelliteBar", { fg = c.border })
	set("SatelliteMark", { fg = c.cyan, bg = c.selection })
	set("SatelliteCursor", { fg = c.brightFg, bg = c.blue })
	set("SatelliteSearch", { fg = c.bg, bg = c.cyan })
	set("SatelliteSearchCurrent", { fg = c.bg, bg = c.blue, bold = true })
	set("SatelliteQuickfix", { fg = c.yellow })
	set("SatelliteDiagnosticError", { fg = c.red })
	set("SatelliteDiagnosticWarn", { fg = c.yellow })
	set("SatelliteDiagnosticInfo", { fg = c.blue })
	set("SatelliteDiagnosticHint", { fg = c.cyan })
	set("SatelliteGitSignsAdd", { fg = c.green })
	set("SatelliteGitSignsChange", { fg = c.orange })
	set("SatelliteGitSignsDelete", { fg = c.red })
	-- Native Claude/codediff and MiniDiff overlays share the palette.
	set("DiffAdd", { bg = blend(c.green, c.deep, 0.08), fg = c.brightFg })
	set("DiffChange", { bg = blend(c.blue, c.deep, 0.08), fg = c.brightFg })
	set("DiffText", { bg = blend(c.blue, c.deep, 0.12), fg = c.brightFg, bold = true })
	set("DiffDelete", { bg = blend(c.red, c.deep, 0.08), fg = c.brightFg })
	set("CodeDiffLineInsert", { bg = blend(c.green, c.deep, 0.08), fg = c.brightFg })
	set("CodeDiffLineDelete", { bg = blend(c.red, c.deep, 0.08), fg = c.brightFg })
	set("CodeDiffCharInsert", { bg = blend(c.green, c.deep, 0.12), fg = c.brightFg, bold = true })
	set("CodeDiffCharDelete", { bg = blend(c.red, c.deep, 0.12), fg = c.brightFg, bold = true })
	set("MiniDiffOverAdd", { link = "DiffAdd" })
	set("MiniDiffOverChange", { link = "DiffChange" })
	set("MiniDiffOverChangeBuf", { link = "DiffText" })
	set("MiniDiffOverContext", { link = "Normal" })
	set("MiniDiffOverDelete", { link = "DiffDelete" })
	set("MayonDiffHint", { fg = c.blue, bg = c.surface, bold = true })
	set("ComplHint", { link = "LspInlineCompletion" })
	set("ComplHintMore", { link = "LspInlineCompletion" })
	set("MinuetVirtualText", { link = "LspInlineCompletion" })
	local links = {
		SoftFloatBorder = "FloatBorder",
		WhichKeyNormal = "NormalFloat",
		WhichKeyBorder = "FloatBorder",
		SnacksInputNormal = "NormalFloat",
		SnacksInputBorder = "FloatBorder",
		SnacksPickerNormal = "NormalFloat",
		SnacksPicker = "NormalFloat",
		SnacksPickerList = "NormalFloat",
		SnacksPickerBorder = "FloatBorder",
		SnacksPickerTitle = "FloatTitle",
		SnacksPickerInput = "NormalFloat",
		SnacksPickerInputBorder = "FloatBorder",
		SnacksPickerBoxBorder = "FloatBorder",
		SnacksPickerListCursorLine = "PmenuSel",
		SnacksPickerPreviewCursorLine = "CursorLine",
		SnacksPickerDirectory = "Directory",
		SnacksPickerTree = "Comment",
		SnacksDashboardNormal = "Normal",
		SnacksDashboardHeader = "MayonDashboardBlue",
		SnacksDashboardFooter = "MayonDashboardMuted",
		SnacksDashboardKey = "MayonDashboardCyan",
		SnacksDashboardTitle = "MayonDashboardBlue",
		SnacksDashboardDesc = "MayonMuted",
		SnacksDashboardFile = "MayonDashboardCyan",
		SnacksDashboardIcon = "MayonDashboardCyan",
		SnacksDashboardSpecial = "MayonDashboardCyan",
		SnacksDashboardDir = "MayonDashboardBlue",
		SnacksIndent = "NonText",
		SnacksIndentScope = "Comment",
		MultiCursorVisual = "Visual",
		MultiCursorSign = "SignColumn",
		MultiCursorMatchPreview = "Search",
		MultiCursorDisabledVisual = "Folded",
		MultiCursorDisabledSign = "SignColumn",
		TroubleNormal = "Normal",
		TroubleNormalNC = "Normal",
	}
	for name, value in pairs({
		Comment = { fg = c.fg, italic = true },
		String = { fg = c.green },
		Number = { fg = c.orange },
		Boolean = { fg = c.orange },
		Constant = { fg = c.orange },
		Function = { fg = c.blue },
		Keyword = { fg = c.cyan },
		Conditional = { fg = c.cyan },
		Repeat = { fg = c.cyan },
		Operator = { fg = c.cyan },
		Exception = { fg = c.cyan },
		PreProc = { fg = c.cyan },
		Include = { fg = c.cyan },
		Define = { fg = c.cyan },
		Macro = { fg = c.cyan },
		Typedef = { fg = c.cyan },
		StorageClass = { fg = c.cyan },
		Structure = { fg = c.cyan },
		Statement = { fg = c.cyan },
		Type = { fg = c.cyan },
		Identifier = { fg = c.brightFg },
		Special = { fg = c.brightFg },
		["@comment"] = { fg = c.fg, italic = true },
		["@string"] = { fg = c.green },
		["@number"] = { fg = c.orange },
		["@boolean"] = { fg = c.orange },
		["@constant"] = { fg = c.orange },
		["@function"] = { fg = c.blue },
		["@function.call"] = { fg = c.blue },
		["@keyword"] = { fg = c.cyan },
		["@keyword.directive"] = { fg = c.cyan },
		["@type"] = { fg = c.cyan },
		["@variable"] = { fg = c.brightFg },
		["@variable.builtin"] = { fg = c.brightFg },
		["@punctuation"] = { fg = c.brightFg },
	}) do
		set(name, value)
	end
	for _, group in ipairs({
		"@keyword.conditional",
		"@keyword.conditional.ternary",
		"@keyword.coroutine",
		"@keyword.debug",
		"@keyword.directive.define",
		"@keyword.exception",
		"@keyword.function",
		"@keyword.import",
		"@keyword.modifier",
		"@keyword.operator",
		"@keyword.repeat",
		"@keyword.return",
		"@keyword.type",
		"@type.builtin",
		"@type.definition",
		"@lsp.type.keyword",
		"@lsp.type.enum",
		"@lsp.type.interface",
		"@lsp.type.typeParameter",
		"@lsp.type.builtinType",
	}) do
		set(group, { fg = c.cyan })
	end
	for _, group in ipairs({
		"@variable.member",
		"@variable.parameter",
		"@variable.parameter.builtin",
		"@punctuation.bracket",
		"@punctuation.delimiter",
		"@punctuation.special",
		"@lsp.type.parameter",
		"@lsp.type.variable",
		"@lsp.typemod.variable.defaultLibrary",
		"@lsp.typemod.variable.injected",
	}) do
		set(group, { fg = c.brightFg })
	end
	for _, group in ipairs({
		"@comment.documentation",
		"@comment.error",
		"@comment.note",
		"@comment.todo",
		"@comment.warning",
	}) do
		set(group, { fg = c.fg, italic = true })
	end
	for _, level in ipairs({ "Error", "Warn", "Info", "Debug", "Trace" }) do
		links["SnacksNotifier" .. level] = "NormalFloat"
		links["SnacksNotifierBorder" .. level] = "FloatBorder"
		local diagnostic = get("DiagnosticSign" .. level)
		local severity = diagnostic.fg or c.muted
		vim.api.nvim_set_hl(0, "SnacksNotifierTitle" .. level, { fg = severity })
		vim.api.nvim_set_hl(0, "SnacksNotifierIcon" .. level, { fg = severity })
	end
	local tiny_colors = {
		Error = c.red,
		Warn = c.yellow,
		Info = c.blue,
		Hint = c.cyan,
	}
	set("TinyInlineDiagnosticVirtualTextBg", { bg = c.bg })
	for name, color in pairs(tiny_colors) do
		set("TinyInlineDiagnosticVirtualText" .. name, { fg = c.brightFg, bg = c.surface })
		set("TinyInlineDiagnosticVirtualText" .. name .. "CursorLine", { fg = c.brightFg, bg = c.selection })
		set("TinyInlineDiagnosticVirtualText" .. name .. "NoBg", { fg = color, bg = "NONE" })
		set("TinyInlineInvDiagnosticVirtualText" .. name, { fg = c.bg, bg = color })
		set("TinyInlineInvDiagnosticVirtualText" .. name .. "CursorLine", { fg = c.bg, bg = color })
		set("TinyInlineInvDiagnosticVirtualText" .. name .. "NoBg", { fg = c.brightFg, bg = "NONE" })
		for mixed_name, mixed_color in pairs(tiny_colors) do
			set("TinyInlineDiagnosticVirtualText" .. name .. "Mix" .. mixed_name, {
				fg = color,
				bg = mixed_color,
			})
		end
	end
	set("TinyInlineDiagnosticVirtualTextArrow", { fg = c.cyan, bg = c.bg })
	set("TinyInlineDiagnosticVirtualTextArrowCursorLine", { fg = c.cyan, bg = c.selection })
	set("TinyInlineDiagnosticVirtualTextArrowNoBg", { fg = c.cyan, bg = "NONE" })
	for name, target in pairs(links) do
		vim.api.nvim_set_hl(0, name, { link = target })
	end
	for name, color in pairs({
		SnacksDashboardNormal = c.fg,
		SnacksDashboardHeader = c.blue,
		SnacksDashboardFooter = c.muted,
		SnacksDashboardKey = c.cyan,
		SnacksDashboardTitle = c.blue,
	}) do
		vim.api.nvim_set_hl(0, name, { fg = color, bg = c.bg })
	end
end

local function configure()
	if configured then
		return
	end
	configured = true
	local c = require("mayon.generated").palette
	require("onedark").setup({
		style = "darker",
		transparent = false,
		term_colors = false,
		toggle_style_list = { "darker" },
		code_style = { comments = "italic" },
		colors = {
			black = c.black,
			bg0 = c.deep,
			bg1 = c.surface,
			bg2 = c.selection,
			bg3 = c.selection,
			bg_blue = c.blue,
			bg_yellow = c.yellow,
			dark_cyan = blend(c.cyan, c.deep, 0.12),
			dark_red = blend(c.red, c.deep, 0.12),
			dark_yellow = blend(c.yellow, c.deep, 0.12),
			dark_purple = blend(c.purple, c.deep, 0.12),
			diff_add = blend(c.green, c.deep, 0.08),
			diff_delete = blend(c.red, c.deep, 0.08),
			diff_change = blend(c.blue, c.deep, 0.08),
			diff_text = blend(c.blue, c.deep, 0.12),
			bg_d = c.deep,
			fg = c.brightFg,
			comment = c.fg,
			grey = c.border,
			light_grey = c.muted,
			blue = c.blue,
			cyan = c.cyan,
			purple = c.purple,
			green = c.green,
			orange = c.orange,
			yellow = c.yellow,
			red = c.red,
		},
	})
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("MayonTheme", { clear = true }),
		callback = overrides,
	})
end

function M.apply()
	configure()
	vim.o.background = "dark"
	-- colorscheme() is the plugin's non-recursive loader; load() runs :colorscheme.
	local ok, cached = false, nil
	if not vim.g.mayon_compile_theme then
		ok, cached = pcall(require, "mayon.generated_highlights")
	end
	if ok then
		vim.cmd("hi clear")
		for name, value in pairs(cached) do
			vim.api.nvim_set_hl(0, name, value)
		end
	else
		-- Development configs can change the adapter without rebuilding its cache.
		require("onedark").colorscheme()
	end
	vim.g.colors_name = "onedark"
	for index, color in ipairs(require("mayon.generated").ansi) do
		vim.g["terminal_color_" .. (index - 1)] = color
	end
end

function M.setup()
	vim.cmd.colorscheme("onedark")
end

M.refresh = overrides

return M
