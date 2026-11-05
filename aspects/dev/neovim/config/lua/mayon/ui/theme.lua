-- One Dark owns syntax/plugin highlights; this adapter restores only the
-- editor surfaces (windows, floats, menus, panels, statusline) without
-- maintaining a second syntax theme.
local M = {}
local configured = false
local util = require("mayon.util")

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

function M.float_edge()
	local c = require("mayon.generated").palette
	return blend(c.border, c.bg, 0.62)
end

local function diagnostic_prefix(diagnostic, index)
	local severity = ({ "Error", "Warn", "Info", "Hint" })[diagnostic.severity]
	return index .. ". ", "Diagnostic" .. severity
end

-- One palette-backed definition for every editing mode. The same table drives
-- the cursor color, the statusline mode mark and the highlight group named here;
-- no second copy of the mode palette exists elsewhere.
local mode_groups = {
	MayonModeNormal = "blue",
	MayonModeInsert = "green",
	MayonModeVisual = "yellow",
	MayonModeReplace = "red",
	MayonModeCommand = "cyan",
}
local modes = {
	n = "MayonModeNormal",
	i = "MayonModeInsert",
	v = "MayonModeVisual",
	V = "MayonModeVisual",
	["\22"] = "MayonModeVisual",
	s = "MayonModeVisual",
	S = "MayonModeVisual",
	["\19"] = "MayonModeVisual",
	R = "MayonModeReplace",
	r = "MayonModeReplace",
	c = "MayonModeCommand",
	["!"] = "MayonModeVisual",
	t = "MayonModeCommand",
}

local function mode_group(mode)
	mode = tostring(mode or "n")
	return modes[mode] or modes[mode:sub(1, 1)] or modes.n
end

function M.mode_highlight(mode)
	return mode_group(mode)
end

-- Resolve a mode to its palette token name ("blue"/"green"/...); callers read
-- the palette once rather than re-parsing a highlight group on every redraw.
function M.mode_token(mode)
	return mode_groups[mode_group(mode)]
end

function M.mode_color(mode)
	local c = require("mayon.generated").palette
	local value = c[M.mode_token(mode)] or c.blue
	return tonumber(value:sub(2), 16)
end

-- Set the cursor (and current-line number) to the active mode color exactly
-- once per mode change, rather than re-deriving highlights on every redraw.
local function apply_mode()
	local c = require("mayon.generated").palette
	local color = M.mode_color(vim.fn.mode(1))
	vim.api.nvim_set_hl(0, "Cursor", { fg = c.bg, bg = color, bold = true })
	vim.api.nvim_set_hl(0, "CursorLineNr", {
		fg = color,
		bg = blend(c.blue, c.bg, 0.035),
		bold = true,
	})
end

local function overrides()
	local c = require("mayon.generated").palette
	local edge = M.float_edge()
	local selection = blend(c.blue, c.bg, 0.10)
	local inactive_bg = c.bg
	local function set(name, values)
		vim.api.nvim_set_hl(0, name, values)
	end

	-- The LSP core sets float options lazily. Merge the numbered severity
	-- marker after it loads; do not load diagnostics on the dashboard or
	-- replace its geometry/options.
	if package.loaded["vim.diagnostic"] then
		local float = vim.diagnostic.config().float
		if type(float) == "table" and float.prefix ~= diagnostic_prefix then
			vim.diagnostic.config({ float = vim.tbl_extend("force", float, { prefix = diagnostic_prefix }) })
		end
	end

	-- Editor surfaces.
	set("Normal", { fg = c.brightFg, bg = c.bg })
	-- Empty rows inherit each window's canvas, including plugin namespaces.
	set("EndOfBuffer", { fg = c.bg, bg = "NONE" })
	set("WinBar", { fg = c.muted, bg = c.bg })
	set("WinBarNC", { fg = c.muted, bg = inactive_bg })
	set("NormalNC", { fg = c.fg, bg = inactive_bg })
	set("Visual", { fg = c.brightFg, bg = selection })
	set("VisualNOS", { fg = c.brightFg, bg = selection })
	set("Search", { fg = c.brightFg, bg = blend(c.orange, c.bg, 0.22) })
	set("IncSearch", { fg = c.deep, bg = c.orange, bold = true })
	set("CurSearch", { fg = c.deep, bg = c.orange, bold = true })
	set("LineNr", { fg = c.muted, bg = c.bg })
	set("CursorLineNr", { fg = c.blue, bg = blend(c.blue, c.bg, 0.035), bold = true })
	set("CursorLine", { bg = blend(c.blue, c.bg, 0.035) })
	set("Cursor", { fg = c.bg, bg = c.blue, bold = true })
	set("CursorLineSign", { bg = c.bg })
	set("SignColumn", { bg = c.bg })
	set("WinSeparator", { fg = edge, bg = c.bg })
	set("NonText", { fg = blend(c.muted, c.bg, 0.62) })
	set("MatchParen", { fg = c.blue, bg = "NONE", bold = true, underline = true, sp = c.blue })
	set("TabLine", { bg = c.bg, fg = c.fg })
	set("TabLineSel", { bg = c.selection, fg = c.brightFg, bold = true })
	set("TabLineFill", { bg = c.bg, fg = c.fg })

	-- Diagnostics: a distinct glyph per severity (the gutter signs are the only
	-- place where all four severities must be readable at a glance).
	for severity, color in pairs({ Error = c.red, Warn = c.yellow, Info = c.blue, Hint = c.cyan }) do
		set("DiagnosticUnderline" .. severity, { sp = blend(color, c.bg, 0.52), undercurl = true })
		set("DiagnosticSign" .. severity, { fg = color, bg = c.bg })
		-- Floating prose stays neutral; the prefix carries the severity color.
		set("DiagnosticFloating" .. severity, { fg = c.brightFg, bg = c.bg })
	end
	set("DiagnosticError", { fg = c.red })
	set("DiagnosticWarn", { fg = c.yellow })
	set("DiagnosticInfo", { fg = c.blue })
	set("DiagnosticHint", { fg = c.cyan })
	set("DiagnosticOk", { fg = c.green })

	local diagnostic_inline = blend(c.yellow, c.bg, 0.62)
	set("MayonDiagnosticInline", { fg = diagnostic_inline, bg = "NONE", italic = true })
	set("LspInlineCompletion", { fg = c.muted, italic = true })
	set("MayonModified", { fg = c.orange, bg = c.bg, bold = true })

	-- Statusline / tabline / panel surfaces.
	set("StatusLine", { fg = c.fg, bg = c.bg })
	set("StatusLineNC", { fg = c.fg, bg = c.bg })
	set("MayonProject", { fg = c.muted, bg = c.bg })
	set("MayonPosition", { fg = c.brightFg, bg = c.bg, bold = true })
	set("MayonHeaderMuted", { fg = c.muted, bg = c.bg })
	set("MayonHeaderFile", { fg = c.brightFg, bg = c.bg })
	set("MayonOutlineRail", { fg = c.blue, bg = selection })
	set("AerialNormal", { fg = c.fg, bg = c.bg })
	set("AerialLine", { fg = c.brightFg, bg = selection })
	set("AerialGuide", { fg = blend(c.border, c.bg, 0.24), bg = c.bg })
	set("AerialGuideLast", { link = "AerialGuide" })
	set("MayonTabAccent", { fg = c.blue, bg = c.bg })
	set("MayonTabVisible", { fg = c.fg, bg = c.bg, bold = true })
	set("MayonMuted", { fg = c.muted })
	set("MayonStatusGit", { fg = c.cyan })
	set("MayonStatusAdded", { fg = c.green })
	set("MayonStatusChanged", { fg = c.orange })
	set("MayonStatusRemoved", { fg = c.red })
	set("MayonFoldText", { fg = c.fg, bg = c.surface })
	set("MayonFoldCount", { fg = c.muted, bg = c.surface })

	-- The single set of mode mark groups; the cursor adopts the same token.
	for group, token in pairs(mode_groups) do
		set(group, { fg = c[token], bg = c.selection, bold = true })
	end

	-- Floating / completion surfaces, all rounded like util.border.
	vim.api.nvim_set_hl(0, "NormalFloat", { fg = c.brightFg, bg = c.bg })
	vim.api.nvim_set_hl(0, "FloatBorder", { fg = edge, bg = c.bg })
	vim.api.nvim_set_hl(0, "FloatTitle", { fg = c.muted, bg = c.bg })
	-- Neogit remaps these names inside its own highlight namespace. Use
	-- concrete colors to avoid a FloatBorder -> NeogitFloatBorder link cycle.
	vim.api.nvim_set_hl(0, "NeogitNormal", { fg = c.brightFg, bg = c.bg })
	vim.api.nvim_set_hl(0, "NeogitNormalFloat", { fg = c.brightFg, bg = c.bg })
	vim.api.nvim_set_hl(0, "NeogitFloatBorder", { fg = edge, bg = c.bg })
	vim.api.nvim_set_hl(0, "NeogitFloatHeader", { fg = c.muted, bg = c.bg })

	set("Pmenu", { fg = c.brightFg, bg = c.bg })
	set("PmenuSel", { fg = c.blue, bg = c.selection, bold = true })
	set("PmenuKind", { fg = c.blue, bg = c.bg })
	set("PmenuKindSel", { fg = c.blue, bg = c.selection })
	set("PmenuExtra", { fg = c.muted, bg = c.bg })
	set("PmenuExtraSel", { fg = c.fg, bg = c.selection })
	set("PmenuBorder", { fg = edge, bg = c.bg })
	set("PmenuSbar", { bg = c.bg })
	set("PmenuThumb", { bg = c.border })
	set("PmenuMatch", { fg = c.blue, bg = c.bg, bold = true })
	set("PmenuMatchSel", { fg = c.blue, bg = c.selection, bold = true })
	set("SnippetTabstopActive", { bg = c.selection, underline = true, sp = c.cyan })

	-- Completion kind icons follow One Dark semantic hues.
	local kind_colors = {
		Function = c.blue,
		Method = c.blue,
		Constructor = c.blue,
		Variable = c.cyan,
		Field = c.cyan,
		Property = c.cyan,
		Class = c.yellow,
		Struct = c.yellow,
		Interface = c.yellow,
		Enum = c.yellow,
		TypeParameter = c.yellow,
		Constant = c.orange,
		Value = c.orange,
		EnumMember = c.orange,
		Unit = c.orange,
		Keyword = c.blue,
		Snippet = c.green,
		Color = c.green,
		File = c.fg,
		Folder = c.blue,
		Reference = c.cyan,
		Event = c.yellow,
		Operator = c.cyan,
		Text = c.fg,
	}
	for name in pairs(require("mayon.kinds")) do
		set("MayonCompletion" .. name, { fg = kind_colors[name] or c.fg })
	end

	-- Markdown presentation (render-markdown owns the icons/background).
	for level, color in ipairs({ c.blue, c.cyan, c.fg, c.fg, c.fg, c.fg }) do
		set("RenderMarkdownH" .. level, { fg = color, bold = true })
		set("@markup.heading." .. level .. ".markdown", { link = "RenderMarkdownH" .. level })
		set("markdownH" .. level, { link = "RenderMarkdownH" .. level })
		set("RenderMarkdownH" .. level .. "Bg", { bg = c.bg })
	end
	set("RenderMarkdownCode", { fg = c.fg, bg = c.bg })
	set("RenderMarkdownCodeInline", { fg = c.cyan, bg = c.bg })
	set("SnacksImageMath", { fg = c.brightFg })
	set("RenderMarkdownCodeBorder", { fg = c.border, bg = c.bg })
	set("RenderMarkdownTableHead", { fg = c.cyan, bold = true })
	set("@markup.heading.markdown", { link = "RenderMarkdownTableHead" })
	set("RenderMarkdownTableRow", { fg = c.border })
	set("RenderMarkdownTableFill", { bg = c.bg })
	set("RenderMarkdownBullet", { fg = c.cyan })
	set("RenderMarkdownQuote", { fg = c.cyan })
	set("RenderMarkdownDash", { fg = c.border })

	-- Rainbow delimiters.
	for name, color in pairs({
		RainbowDelimiterRed = c.red,
		RainbowDelimiterYellow = c.yellow,
		RainbowDelimiterBlue = c.blue,
		RainbowDelimiterOrange = c.orange,
		RainbowDelimiterGreen = c.green,
		RainbowDelimiterViolet = c.blue,
		RainbowDelimiterCyan = c.cyan,
	}) do
		vim.api.nvim_set_hl(0, name, { fg = color })
	end

	-- TODO comments.
	for todo, color in pairs({
		FIX = c.red,
		TODO = c.blue,
		HACK = c.orange,
		WARN = c.orange,
		PERF = c.blue,
		NOTE = c.cyan,
		TEST = c.green,
	}) do
		vim.api.nvim_set_hl(0, "TodoFg" .. todo, { fg = color, bold = true })
		vim.api.nvim_set_hl(0, "TodoBg" .. todo, { fg = c.bg, bg = color, bold = true })
		vim.api.nvim_set_hl(0, "TodoSign" .. todo, { fg = color })
	end

	-- Oil file browser.
	set("OilDir", { fg = c.blue, bold = true })
	set("OilDirIcon", { fg = c.cyan })
	set("OilDirHidden", { fg = c.muted, bold = true })
	set("OilFile", { fg = c.fg })
	set("OilFileHidden", { fg = c.muted })
	set("OilSocket", { fg = c.cyan })
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

	-- Secondary plugin surfaces.
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

	set("GitSignsAdd", { fg = c.green, bg = c.bg })
	set("GitSignsChange", { fg = c.blue, bg = c.bg })
	set("GitSignsDelete", { fg = c.red, bg = c.bg })

	-- Native Claude/codediff and MiniDiff overlays share the palette.
	set("DiffAdd", { bg = blend(c.green, c.bg, 0.12), fg = c.brightFg })
	set("DiffChange", { bg = blend(c.blue, c.bg, 0.12), fg = c.brightFg })
	set("DiffText", { bg = blend(c.blue, c.bg, 0.18), fg = c.brightFg, bold = true })
	set("DiffDelete", { bg = blend(c.red, c.bg, 0.12), fg = c.brightFg })
	set("CodeDiffLineInsert", { bg = blend(c.green, c.bg, 0.12), fg = c.brightFg })
	set("CodeDiffLineDelete", { bg = blend(c.red, c.bg, 0.12), fg = c.brightFg })
	set("CodeDiffCharInsert", { bg = blend(c.green, c.bg, 0.18), fg = c.brightFg, bold = true })
	set("CodeDiffCharDelete", { bg = blend(c.red, c.bg, 0.18), fg = c.brightFg, bold = true })
	set("MiniDiffOverAdd", { link = "DiffAdd" })
	set("MiniDiffOverChange", { link = "DiffChange" })
	set("MiniDiffOverChangeBuf", { link = "DiffText" })
	set("MiniDiffOverContext", { link = "Normal" })
	set("MiniDiffOverDelete", { link = "DiffDelete" })
	set("MayonDiffHint", { fg = c.blue, bg = c.bg, bold = true })

	set("Directory", { fg = c.blue, bold = true })

	-- AI ghost text and inline diagnostics share a single muted styling.
	set("ComplHint", { link = "LspInlineCompletion" })
	set("ComplHintMore", { link = "LspInlineCompletion" })
	set("MinuetVirtualText", { link = "LspInlineCompletion" })

	set("MayonPopup", { fg = c.brightFg, bg = c.bg })
	set("MayonPopupBorder", { fg = edge, bg = c.bg })
	set("MayonPopupTitle", { fg = c.muted, bg = c.bg })
	set("MayonFloatErrorBorder", { fg = blend(c.red, c.bg, 0.65), bg = c.bg })
	set("MayonExplorerFile", { fg = c.fg })
	set("MayonExplorerTitle", { fg = c.muted, bg = c.bg })
	set("MayonExplorerDirectory", { fg = c.fg, bg = c.bg })
	set("MayonIndentGuide", { fg = blend(c.border, c.bg, 0.16) })
	set("MayonIndentScope", { fg = blend(c.border, c.bg, 0.34) })

	for _, group in ipairs({ "LspReferenceText", "LspReferenceRead" }) do
		set(group, { fg = c.fg, bg = "NONE", underline = true, sp = blend(c.blue, c.bg, 0.28) })
	end
	set("LspReferenceWrite", { fg = c.fg, bg = "NONE", underline = true, sp = blend(c.blue, c.bg, 0.38) })

	set("SnacksPickerListCursorLine", { bg = c.selection })
	set("SnacksPickerPreview", { fg = c.brightFg, bg = c.bg })
	set("SnacksPickerDimmed", { fg = blend(c.muted, c.bg, 0.5) })
	set("MayonNotificationTitle", { fg = c.brightFg, bg = c.bg })
	set("MayonNotificationBody", { fg = c.fg, bg = c.bg })
	set("MayonPanelTitle", { fg = c.muted, bg = c.bg })
	set("MayonCompletionRail", { fg = c.blue, bg = c.selection })
	set("MayonPreviewLine", { bg = blend(c.blue, c.bg, 0.12) })

	for name, spec in pairs({
		SnacksPickerPrompt = { fg = c.blue, bold = true },
		SnacksPickerMatch = { fg = c.blue, bold = true },
		MayonPickerRail = { fg = c.blue, bg = c.selection },
		MayonPickerSource = { fg = c.brightFg, bg = c.bg },
		MayonPickerRange = { fg = c.muted, bg = c.bg },
		MayonPickerCount = { fg = c.muted, bg = c.bg },
		SnacksPickerRow = { fg = c.border },
		SnacksPickerCol = { fg = c.border },
		SnacksPickerFile = { fg = c.brightFg },
		SnacksPickerTotals = { fg = c.muted },
		FlashLabel = { fg = c.bg, bg = c.blue, bold = true },
		FlashMatch = { fg = c.blue, bg = c.selection },
		FlashCurrent = { fg = c.brightFg, bg = c.selection, bold = true },
		HealthNormal = { fg = c.brightFg, bg = c.bg },
		MsgArea = { fg = c.fg, bg = c.bg },
		MsgSeparator = { fg = edge, bg = c.bg },
		Question = { fg = c.blue, bold = true },
		MoreMsg = { fg = c.muted },
	}) do
		set(name, spec)
	end

	-- Highlight links: plugin window groups inherit the unified surfaces.
	local links = {
		SoftFloatBorder = "FloatBorder",
		WhichKeyNormal = "MayonPopup",
		WhichKeyBorder = "MayonPopupBorder",
		SnacksInputNormal = "MayonPopup",
		SnacksInputBorder = "MayonPopupBorder",
		SnacksInputTitle = "FloatTitle",
		SnacksPickerNormal = "MayonPopup",
		SnacksPicker = "MayonPopup",
		SnacksPickerList = "MayonPopup",
		SnacksPickerBorder = "MayonPopupBorder",
		SnacksPickerTitle = "FloatTitle",
		SnacksPickerInput = "MayonPopup",
		SnacksPickerInputBorder = "MayonPopupBorder",
		SnacksPickerBoxBorder = "MayonPopupBorder",
		SnacksPickerBox = "MayonPopup",
		SnacksPickerPreviewBorder = "MayonPopupBorder",
		FloatFooter = "FloatTitle",
		SnacksPickerPreviewCursorLine = "MayonPreviewLine",
		SnacksPickerDirectory = "MayonExplorerDirectory",
		SnacksPickerTree = "MayonIndentGuide",
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
		SnacksIndent = "MayonIndentGuide",
		SnacksIndentScope = "MayonIndentScope",
		SnacksPickerGitStatusModified = "MayonStatusChanged",
		MultiCursorVisual = "Visual",
		MultiCursorSign = "SignColumn",
		MultiCursorMatchPreview = "Search",
		MultiCursorDisabledVisual = "Folded",
		MultiCursorDisabledSign = "SignColumn",
		TroubleNormal = "NormalFloat",
		TroubleNormalNC = "NormalFloat",
	}

	set("MultiCursorCursor", { fg = c.bg, bg = c.cyan, bold = true })
	set("MultiCursorDisabledCursor", { fg = c.bg, bg = c.muted })

	-- Treesitter context header.
	set("TreesitterContext", { bg = c.bg })
	set("TreesitterContextLineNumber", { bg = c.bg, fg = c.fg })
	set("TreesitterContextSeparator", { fg = c.border, bg = c.bg })

	-- Snacks notifier: severity-colored icon marks, muted body text.
	for _, level in ipairs({ "Error", "Warn", "Info", "Debug", "Trace" }) do
		links["SnacksNotifier" .. level] = "NormalFloat"
		links["SnacksNotifierBorder" .. level] = "FloatBorder"
		local sign = vim.api.nvim_get_hl(0, { name = "DiagnosticSign" .. level, link = false })
		local severity = sign.fg or c.muted
		vim.api.nvim_set_hl(0, "SnacksNotifierTitle" .. level, { fg = c.muted, bg = c.bg })
		vim.api.nvim_set_hl(0, "SnacksNotifierIcon" .. level, { fg = severity, bg = c.bg })
	end
	for name, target in pairs(links) do
		vim.api.nvim_set_hl(0, name, { link = target })
	end

	-- tiny-inline-diagnostic: one restrained italic body color across all
	-- severity permutations (signs and undercurls carry the real severity).
	set("TinyInlineDiagnosticVirtualTextBg", { bg = "NONE" })
	for _, name in ipairs({ "Error", "Warn", "Info", "Hint" }) do
		for _, suffix in ipairs({ "", "CursorLine", "NoBg" }) do
			set("TinyInlineDiagnosticVirtualText" .. name .. suffix, {
				fg = diagnostic_inline,
				bg = "NONE",
				italic = true,
			})
			set("TinyInlineInvDiagnosticVirtualText" .. name .. suffix, {
				fg = diagnostic_inline,
				bg = "NONE",
				italic = true,
			})
		end
		for _, secondary in ipairs({ "Error", "Warn", "Info", "Hint" }) do
			set("TinyInlineDiagnosticVirtualText" .. name .. "Mix" .. secondary, {
				fg = diagnostic_inline,
				bg = "NONE",
				italic = true,
			})
		end
	end
	for _, suffix in ipairs({ "", "CursorLine", "NoBg" }) do
		set("TinyInlineDiagnosticVirtualTextArrow" .. suffix, { fg = diagnostic_inline, bg = "NONE", italic = true })
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
			bg1 = c.bg,
			bg2 = c.selection,
			bg3 = c.selection,
			bg_blue = c.blue,
			bg_yellow = c.yellow,
			dark_cyan = blend(c.cyan, c.deep, 0.12),
			dark_red = blend(c.red, c.deep, 0.12),
			dark_yellow = blend(c.yellow, c.deep, 0.12),
			dark_purple = blend(c.blue, c.deep, 0.12),
			diff_add = blend(c.green, c.bg, 0.12),
			diff_delete = blend(c.red, c.bg, 0.12),
			diff_change = blend(c.blue, c.bg, 0.12),
			diff_text = blend(c.blue, c.bg, 0.18),
			bg_d = c.bg,
			fg = c.brightFg,
			comment = c.fg,
			grey = c.border,
			light_grey = c.muted,
			blue = c.blue,
			cyan = c.cyan,
			purple = c.blue,
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
	-- One rounded frame for every float that does not pass an explicit border.
	vim.o.winborder = util.border
	vim.cmd.colorscheme("onedark")

	-- Only the focused document draws its cursorline. An inactive document maps
	-- its cursor-line groups to NormalNC/LineNr; the original links are restored
	-- on focus. This touches two known links instead of parsing and rebuilding a
	-- stateful 'winhighlight' string on every window switch.
	local inactive_links = setmetatable({}, { __mode = "k" })
	local function document_window()
		local buf = vim.api.nvim_get_current_buf()
		return vim.bo[buf].buftype == "" and not vim.b[buf].snacks_dashboard
	end
	local function clean_document_surface()
		if vim.api.nvim_win_get_config(0).relative ~= "" then
			return
		end
		local links = util.winhl_parse(vim.wo.winhighlight)
		for from, to in pairs(links) do
			if
				to:match("^SnacksDashboard")
				or ((from == "Normal" or from == "NormalNC") and to == "NormalFloat")
				or (from == "WinBar" and to == "MayonPanelTitle")
				or (from == "WinSeparator" and to == "FloatBorder")
				or (from == "CursorLine" and to == "PmenuSel")
			then
				links[from] = nil
			end
		end
		vim.wo.winhighlight = util.winhl_string(links)
	end
	local function deactivate()
		if not document_window() then
			return
		end
		local win = vim.api.nvim_get_current_win()
		-- Keep the first saved original: a WinLeave without a matching WinEnter
		-- (noautocmd focus changes) must not record the inactive mapping itself.
		if not inactive_links[win] then
			local links = util.winhl_parse(vim.wo[win].winhighlight)
			local saved = { CursorLine = links.CursorLine, CursorLineNr = links.CursorLineNr }
			if saved.CursorLine == "NormalNC" then
				saved.CursorLine = nil
			end
			if saved.CursorLineNr == "LineNr" then
				saved.CursorLineNr = nil
			end
			inactive_links[win] = saved
		end
		util.winhl(win, { CursorLine = "NormalNC", CursorLineNr = "LineNr" })
	end
	local function activate()
		local win = vim.api.nvim_get_current_win()
		local saved = inactive_links[win]
		if saved then
			inactive_links[win] = nil
			local current = util.winhl_parse(vim.wo[win].winhighlight)
			if current.CursorLine == "NormalNC" then
				util.winhl(win, {
					CursorLine = saved.CursorLine or false,
					CursorLineNr = saved.CursorLineNr or false,
				})
			end
		end
		if document_window() then
			clean_document_surface()
		end
	end
	local group = vim.api.nvim_create_augroup("MayonActiveSurface", { clear = true })
	vim.api.nvim_create_autocmd("WinLeave", { group = group, callback = deactivate })
	vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter" }, {
		group = group,
		callback = function()
			activate()
			apply_mode()
		end,
	})
	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		callback = function(ev)
			inactive_links[tonumber(ev.match)] = nil
		end,
	})
	vim.api.nvim_create_autocmd("ModeChanged", { group = group, callback = apply_mode })
	apply_mode()
end

M.refresh = overrides

return M
