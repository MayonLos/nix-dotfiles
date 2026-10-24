-- One Dark Darker owns syntax/plugin highlights; this adapter restores the
-- editor surfaces without maintaining a second syntax theme.
local M = {}
local configured = false

local function overrides()
	local function get(name)
		return vim.api.nvim_get_hl(0, { name = name, link = false })
	end
	local c = require("mayon.generated").palette
	local function set(name, values)
		vim.api.nvim_set_hl(0, name, values)
	end
	set("StatusLine", { fg = c.fg, bg = c.bg })
	set("StatusLineNC", { fg = c.muted, bg = c.bg })
	set("MayonProject", { fg = c.blue, bg = c.surface, bold = true })
	set("MayonPosition", { fg = c.brightFg, bg = c.surface, bold = true })
	set("MayonTabAccent", { fg = c.blue, bg = c.surface })
	set("MayonTabVisible", { fg = c.fg, bg = c.bg, bold = true })
	set("MayonMuted", { fg = c.muted })
	set("MayonDashboardBlue", { fg = c.blue, bold = true })
	set("MayonDashboardMix", { fg = c.cyan, bold = true })
	set("MayonDashboardCyan", { fg = c.cyan, bold = true })
	set("MayonDashboardMuted", { fg = c.muted })
	set("MayonModeNormal", { fg = c.bg, bg = c.blue, bold = true })
	set("MayonModeInsert", { fg = c.bg, bg = c.green, bold = true })
	set("MayonModeVisual", { fg = c.bg, bg = c.purple, bold = true })
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
	set("DapBreakpoint", { fg = c.red, bold = true })
	set("DapBreakpointCondition", { fg = c.orange, bold = true })
	set("DapBreakpointRejected", { fg = c.muted })
	vim.api.nvim_set_hl(0, "NormalFloat", { fg = c.fg, bg = c.bg })
	vim.api.nvim_set_hl(0, "FloatBorder", { fg = c.border, bg = c.bg })
	vim.api.nvim_set_hl(0, "FloatTitle", { fg = c.blue, bg = c.bg, bold = true })
	vim.api.nvim_set_hl(0, "MultiCursorCursor", { fg = c.bg, bg = c.cyan, bold = true })
	vim.api.nvim_set_hl(0, "MultiCursorDisabledCursor", { fg = c.bg, bg = c.muted })
	local match = get("MatchParen")
	match.bold, match.underline = true, true
	vim.api.nvim_set_hl(0, "MatchParen", match)
	set("TabLine", { bg = c.bg, fg = c.muted })
	set("TabLineSel", { bg = c.surface, fg = c.brightFg, bold = true, underline = true, sp = c.blue })
	set("TabLineFill", { bg = c.bg, fg = c.muted })
	set("TreesitterContext", { bg = c.surface })
	set("TreesitterContextLineNumber", { bg = c.surface, fg = c.muted })
	set("TreesitterContextSeparator", { fg = c.border, bg = c.surface })
	set("Pmenu", { fg = c.fg, bg = c.bg })
	set("PmenuSel", { fg = c.brightFg, bg = c.selection, bold = true })
	set("BlinkCmpMenuSelection", { fg = c.brightFg, bg = c.selection, bold = true })
	set("BlinkCmpDocSeparator", { fg = c.border, bg = c.bg })
	set("BlinkCmpSignatureActiveParameter", { fg = c.cyan, bg = c.bg, underline = true })
	set("BlinkCmpSignatureHelpActiveParameter", { fg = c.cyan, bg = c.bg, underline = true })
	set("BlinkCmpLabel", { fg = c.brightFg })
	set("BlinkCmpLabelMatch", { fg = c.cyan, bold = true })
	-- Completion details and sources carry useful reading context; reserve muted
	-- text for inactive chrome and decoration.
	set("BlinkCmpLabelDetail", { fg = c.fg })
	set("BlinkCmpLabelDescription", { fg = c.fg })
	set("BlinkCmpSource", { fg = c.fg, italic = true })
	set("BlinkCmpGhostText", { fg = c.border, italic = true })
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
	set("NvimDapVirtualText", { fg = c.muted, bg = c.surface })
	set("NvimDapVirtualTextChanged", { fg = c.orange, bg = c.surface })
	set("NvimDapVirtualTextError", { fg = c.red, bg = c.surface })
	set("NvimDapVirtualTextInfo", { fg = c.blue, bg = c.surface })
	set("NvimDapViewFloat", { fg = c.orange })
	set("NvimDapViewMissingData", { fg = c.red })
	set("NvimDapViewFileName", { fg = c.cyan, bold = true })
	set("NvimDapViewLineNumber", { fg = c.muted })
	set("NvimDapViewSeparator", { fg = c.border })
	set("NvimDapViewThread", { fg = c.blue })
	set("NvimDapViewThreadStopped", { fg = c.yellow, bold = true })
	set("NvimDapViewThreadError", { fg = c.red, bold = true })
	set("NvimDapViewFrameCurrent", { fg = c.yellow, bg = c.selection, bold = true })
	set("NvimDapViewExceptionFilterEnabled", { fg = c.green })
	set("NvimDapViewExceptionFilterDisabled", { fg = c.red })
	set("NvimDapViewTab", { fg = c.muted, bg = c.bg })
	set("NvimDapViewTabSelected", { fg = c.brightFg, bg = c.surface, bold = true })
	set("NvimDapViewTabFill", { fg = c.muted, bg = c.bg })
	set("NvimDapViewControlNC", { fg = c.muted })
	set("NvimDapViewControlPlay", { fg = c.green })
	set("NvimDapViewControlPause", { fg = c.yellow })
	set("NvimDapViewControlStepInto", { fg = c.blue })
	set("NvimDapViewControlStepOut", { fg = c.blue })
	set("NvimDapViewControlStepOver", { fg = c.blue })
	set("NvimDapViewControlStepBack", { fg = c.blue })
	set("NvimDapViewControlRunLast", { fg = c.cyan })
	set("NvimDapViewControlTerminate", { fg = c.red })
	set("NvimDapViewControlDisconnect", { fg = c.red })
	set("NvimDapViewWatchExpr", { fg = c.cyan })
	set("NvimDapViewWatchError", { fg = c.red })
	set("NvimDapViewWatchUpdated", { fg = c.yellow })
	set("NvimDapViewBoolean", { fg = c.purple })
	set("NvimDapViewBooleanDim", { fg = c.purple, blend = 30 })
	set("NvimDapViewString", { fg = c.green })
	set("NvimDapViewStringDim", { fg = c.green, blend = 30 })
	set("NvimDapViewNumber", { fg = c.orange })
	set("NvimDapViewNumberDim", { fg = c.orange, blend = 30 })
	set("NvimDapViewFloat", { fg = c.orange })
	set("NvimDapViewFloatDim", { fg = c.orange, blend = 30 })
	set("NvimDapViewFunction", { fg = c.blue })
	set("NvimDapViewFunctionDim", { fg = c.blue, blend = 30 })
	set("NvimDapViewConstant", { fg = c.cyan })
	set("NvimDapViewConstantDim", { fg = c.cyan, blend = 30 })
	set("NvimDapViewVirtualText", { fg = c.muted })
	set("NvimDapViewVirtualTextUpdated", { fg = c.orange, blend = 30 })
	set("OverseerPENDING", { fg = c.muted })
	set("OverseerRUNNING", { fg = c.blue, bold = true })
	set("OverseerSUCCESS", { fg = c.green })
	set("OverseerCANCELED", { fg = c.orange })
	set("OverseerFAILURE", { fg = c.red, bold = true })
	set("OverseerTask", { fg = c.fg })
	set("OverseerTaskBorder", { fg = c.border })
	set("OverseerOutput", { fg = c.fg })
	set("OverseerComponent", { fg = c.muted })
	set("OverseerField", { fg = c.cyan })
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
		set("TinyInlineDiagnosticVirtualText" .. name, { fg = color, bg = c.surface })
		set("TinyInlineDiagnosticVirtualText" .. name .. "CursorLine", { fg = color, bg = c.selection })
		set("TinyInlineDiagnosticVirtualText" .. name .. "NoBg", { fg = color, bg = "NONE" })
		set("TinyInlineInvDiagnosticVirtualText" .. name, { fg = c.bg, bg = color })
		set("TinyInlineInvDiagnosticVirtualText" .. name .. "CursorLine", { fg = c.bg, bg = color })
		set("TinyInlineInvDiagnosticVirtualText" .. name .. "NoBg", { fg = color, bg = "NONE" })
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
	for name in pairs(vim.api.nvim_get_hl(0, {})) do
		if name:match("^NoiceCmdlinePopupBorder") then
			links[name] = "FloatBorder"
		end
	end
	for name, target in pairs(links) do
		vim.api.nvim_set_hl(0, name, { link = target })
	end
	for name, color in pairs({
		NoiceCmdlinePopup = c.fg,
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
			bg0 = c.bg,
			bg1 = c.surface,
			bg2 = c.selection,
			bg_d = c.bg,
			fg = c.fg,
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
	require("onedark").colorscheme()
	overrides()
	vim.g.colors_name = "onedark-darker"
	for index, color in ipairs(require("mayon.generated").ansi) do
		vim.g["terminal_color_" .. (index - 1)] = color
	end
end

function M.setup()
	vim.cmd.colorscheme("onedark-darker")
end

M.refresh = overrides

return M
