-- One Dark owns syntax/plugin highlights; this adapter restores the
-- editor surfaces without maintaining a second syntax theme.
local M = {}
local configured = false
local surface_winhighlight = {}

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
	return blend(c.border, c.deep, 0.42)
end

local function overrides()
	local function get(name)
		return vim.api.nvim_get_hl(0, { name = name, link = false })
	end
	local c = require("mayon.generated").palette
	local edge = M.float_edge()
	local separator = edge
	local selection = blend(c.blue, c.bg, 0.14)
	local inactive_bg = blend("#000000", c.bg, 0.06)
	local function set(name, values)
		vim.api.nvim_set_hl(0, name, values)
	end
	set("Normal", { fg = c.brightFg, bg = c.bg })
	-- Empty rows inherit each window's canvas, including plugin namespaces.
	set("EndOfBuffer", { fg = c.bg, bg = "NONE" })
	set("WinBar", { fg = c.muted, bg = c.bg })
	set("WinBarNC", { fg = c.dim, bg = inactive_bg })
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
	set("WinSeparator", { fg = separator, bg = c.bg })
	set("NonText", { fg = blend(c.muted, c.bg, 0.62) })
	for severity, color in pairs({ Error = c.red, Warn = c.yellow, Info = c.blue, Hint = c.cyan }) do
		set("DiagnosticUnderline" .. severity, { sp = blend(color, c.bg, 0.52), undercurl = true })
		set("DiagnosticSign" .. severity, { fg = blend(color, c.bg, 0.72), bg = c.bg })
	end
	local diagnostic_inline = blend(c.yellow, c.bg, 0.62)
	set("MayonDiagnosticInline", { fg = diagnostic_inline, bg = "NONE", italic = true })
	set("MayonModified", { fg = c.orange, bg = c.deep, bold = true })
	set("StatusLine", { fg = c.fg, bg = c.deep })
	set("StatusLineNC", { fg = c.fg, bg = c.deep })
	set("MayonDashboardMode", { fg = c.blue, bg = c.selection, bold = true })
	set("MayonProject", { fg = c.muted, bg = c.deep })
	set("MayonPosition", { fg = c.brightFg, bg = c.surface, bold = true })
	set("MayonTabAccent", { fg = c.blue, bg = c.bg })
	set("MayonTabVisible", { fg = c.fg, bg = c.deep, bold = true })
	set("MayonMuted", { fg = c.muted })
	set("MayonDashboardBlue", { fg = c.blue, bold = true })
	set("MayonDashboardMix", { fg = c.cyan, bold = true })
	set("MayonDashboardCyan", { fg = c.cyan, bold = true })
	set("MayonDashboardMuted", { fg = c.muted })
	set("MayonModeNormal", { fg = c.blue, bg = c.deep, bold = true, underline = true, sp = c.blue })
	set("MayonModeInsert", { fg = c.green, bg = c.deep, bold = true, underline = true, sp = c.green })
	set("MayonModeVisual", { fg = c.yellow, bg = c.deep, bold = true, underline = true, sp = c.yellow })
	set("MayonModeReplace", { fg = c.red, bg = c.deep, bold = true, underline = true, sp = c.red })
	set("MayonModeCommand", { fg = c.orange, bg = c.deep, bold = true, underline = true, sp = c.orange })
	set("MayonModeBlockNormal", { fg = c.blue, bg = c.selection, bold = true })
	set("MayonModeBlockInsert", { fg = c.green, bg = c.selection, bold = true })
	set("MayonModeBlockVisual", { fg = c.purple, bg = c.selection, bold = true })
	set("MayonModeBlockReplace", { fg = c.red, bg = c.selection, bold = true })
	set("MayonModeBlockCommand", { fg = c.yellow, bg = c.selection, bold = true })
	set("MayonFoldText", { fg = c.fg, bg = c.surface })
	set("MayonFoldCount", { fg = c.muted, bg = c.surface })
	set("MayonStatusGit", { fg = c.cyan })
	set("MayonStatusAdded", { fg = c.green })
	set("MayonStatusChanged", { fg = c.orange })
	set("MayonStatusRemoved", { fg = c.red })
	set("DiagnosticError", { fg = c.red })
	set("DiagnosticWarn", { fg = c.yellow })
	set("DiagnosticInfo", { fg = c.blue })
	set("DiagnosticHint", { fg = c.cyan })
	set("DiagnosticOk", { fg = c.green })
	set("DiagnosticSignError", { fg = blend(c.red, c.bg, 0.62), bg = c.bg })
	set("DiagnosticSignWarn", { fg = blend(c.yellow, c.bg, 0.62), bg = c.bg })
	set("DiagnosticSignInfo", { fg = blend(c.blue, c.bg, 0.62), bg = c.bg })
	set("DiagnosticSignHint", { fg = blend(c.cyan, c.bg, 0.62), bg = c.bg })
	set("DiagnosticSignOk", { fg = c.green })
	vim.api.nvim_set_hl(0, "NormalFloat", { fg = c.brightFg, bg = c.deep })
	vim.api.nvim_set_hl(0, "FloatBorder", { fg = edge, bg = c.deep })
	vim.api.nvim_set_hl(0, "FloatTitle", { fg = c.muted, bg = c.deep })
	-- Neogit remaps these names inside its own highlight namespace. Use
	-- concrete colors to avoid a FloatBorder -> NeogitFloatBorder link cycle.
	vim.api.nvim_set_hl(0, "NeogitNormal", { fg = c.brightFg, bg = c.deep })
	vim.api.nvim_set_hl(0, "NeogitNormalFloat", { fg = c.brightFg, bg = c.deep })
	vim.api.nvim_set_hl(0, "NeogitFloatBorder", { fg = edge, bg = c.deep })
	vim.api.nvim_set_hl(0, "NeogitFloatHeader", { fg = c.muted, bg = c.deep })
	vim.api.nvim_set_hl(0, "MultiCursorCursor", { fg = c.bg, bg = c.cyan, bold = true })
	vim.api.nvim_set_hl(0, "MultiCursorDisabledCursor", { fg = c.bg, bg = c.muted })
	set("MatchParen", { fg = c.blue, bg = "NONE", bold = true, underline = true, sp = c.blue })
	set("TabLine", { bg = c.deep, fg = c.fg })
	set("TabLineSel", { bg = c.selection, fg = c.brightFg, bold = true })
	set("TabLineFill", { bg = c.deep, fg = c.fg })
	set("TreesitterContext", { bg = c.surface })
	set("TreesitterContextLineNumber", { bg = c.surface, fg = c.fg })
	set("TreesitterContextSeparator", { fg = c.border, bg = c.surface })
	set("Pmenu", { fg = c.brightFg, bg = c.deep })
	set("PmenuSel", { fg = c.brightFg, bg = c.selection, bold = true })
	set("PmenuKind", { fg = c.blue, bg = c.deep })
	set("PmenuKindSel", { fg = c.blue, bg = c.selection })
	set("PmenuExtra", { fg = c.muted, bg = c.deep })
	set("PmenuExtraSel", { fg = c.muted, bg = c.selection })
	set("PmenuBorder", { fg = edge, bg = c.deep })
	set("PmenuSbar", { bg = c.surface })
	set("PmenuThumb", { bg = c.border })
	set("PmenuMatch", { fg = c.blue, bg = c.deep, bold = true })
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
	set("MayonDiffHint", { fg = c.blue, bg = c.deep, bold = true })
	set("ComplHint", { link = "LspInlineCompletion" })
	set("ComplHintMore", { link = "LspInlineCompletion" })
	set("MinuetVirtualText", { link = "LspInlineCompletion" })
	set("Directory", { fg = c.blue, bold = true })
	set("MayonPopup", { fg = c.brightFg, bg = c.deep })
	set("MayonPopupBorder", { fg = edge, bg = c.deep })
	set("MayonPopupTitle", { fg = c.muted, bg = c.deep })
	set("MayonExplorerFile", { fg = c.fg })
	set("MayonExplorerTitle", { fg = c.muted, bg = c.deep })
	set("MayonExplorerDirectory", { fg = c.fg, bg = c.deep })
	set("MayonExplorerCursor", { fg = c.blue, bg = c.selection, bold = true })
	set("MayonIndentGuide", { fg = blend(c.border, c.bg, 0.16) })
	set("MayonIndentScope", { fg = blend(c.border, c.bg, 0.34) })
	for _, group in ipairs({ "LspReferenceText", "LspReferenceRead" }) do
		set(group, { fg = c.fg, bg = "NONE", underline = true, sp = blend(c.blue, c.bg, 0.28) })
	end
	set("LspReferenceWrite", { fg = c.fg, bg = "NONE", underline = true, sp = blend(c.blue, c.bg, 0.38) })
	set("SnacksPickerListCursorLine", { bg = c.selection })
	set("SnacksPickerPreview", { fg = c.brightFg, bg = c.deep })
	set("SnacksPickerDimmed", { fg = blend(c.muted, c.deep, 0.5) })
	set("MayonNotificationTitle", { fg = c.brightFg, bg = c.deep })
	set("MayonNotificationBody", { fg = c.muted, bg = c.deep })
	set("MayonPanelTitle", { fg = c.muted, bg = c.deep })
	set("MayonCompletionRail", { fg = c.blue, bg = c.selection })
	set("MayonPreviewLine", { bg = blend(c.blue, c.deep, 0.12) })
	for name, spec in pairs({
		SnacksPickerPrompt = { fg = c.blue, bold = true },
		SnacksPickerMatch = { fg = c.blue, bold = true },
		MayonPickerRail = { fg = c.blue, bg = c.selection },
		MayonPickerSource = { fg = c.brightFg, bg = c.deep },
		MayonPickerRange = { fg = c.muted, bg = c.deep },
		MayonPickerCount = { fg = c.muted, bg = c.deep },
		SnacksPickerRow = { fg = c.border },
		SnacksPickerCol = { fg = c.border },
		SnacksPickerFile = { fg = c.brightFg },
		SnacksPickerTotals = { fg = c.muted },
		FlashLabel = { fg = c.bg, bg = c.blue, bold = true },
		FlashMatch = { fg = c.blue, bg = c.selection },
		FlashCurrent = { fg = c.brightFg, bg = c.selection, bold = true },
		HealthNormal = { fg = c.brightFg, bg = c.deep },
		MsgArea = { fg = c.fg, bg = c.deep },
		MsgSeparator = { fg = edge, bg = c.deep },
		Question = { fg = c.blue, bold = true },
		MoreMsg = { fg = c.muted },
	}) do
		set(name, spec)
	end
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
		SnacksPickerPreviewCursorLine = "MayonPreviewLine",
		SnacksPickerDirectory = "MayonExplorerDirectory",
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
	for name, value in pairs({
		Comment = { fg = c.muted, italic = true },
		String = { fg = c.green },
		Number = { fg = c.orange },
		Boolean = { fg = c.orange },
		Constant = { fg = c.orange },
		Function = { fg = c.blue },
		Keyword = { fg = c.purple },
		Conditional = { fg = c.purple },
		Repeat = { fg = c.purple },
		Operator = { fg = c.cyan },
		Exception = { fg = c.purple },
		PreProc = { fg = c.purple },
		Include = { fg = c.purple },
		Define = { fg = c.purple },
		Macro = { fg = c.purple },
		Typedef = { fg = c.cyan },
		StorageClass = { fg = c.purple },
		Structure = { fg = c.cyan },
		Statement = { fg = c.purple },
		Type = { fg = c.cyan },
		Identifier = { fg = c.brightFg },
		Special = { fg = c.brightFg },
		["@comment"] = { fg = c.muted, italic = true },
		["@string"] = { fg = c.green },
		["@number"] = { fg = c.orange },
		["@boolean"] = { fg = c.orange },
		["@constant"] = { fg = c.orange },
		["@function"] = { fg = c.blue },
		["@function.call"] = { fg = c.blue },
		["@lsp.type.function"] = { fg = c.blue },
		["@keyword"] = { fg = c.purple },
		["@keyword.directive"] = { fg = c.purple },
		["@type"] = { fg = c.cyan },
		["@variable"] = { fg = c.fg },
		["@variable.builtin"] = { fg = c.fg },
		["@lsp.type.variable"] = { fg = c.fg },
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
		set(group, { fg = group:find("keyword", 1, true) and c.purple or c.yellow })
	end
	for _, group in ipairs({
		"@punctuation.bracket",
		"@punctuation.delimiter",
		"@punctuation.special",
	}) do
		set(group, { fg = c.brightFg })
	end
	for _, group in ipairs({ "@variable.parameter", "@variable.parameter.builtin", "@lsp.type.parameter" }) do
		set(group, { fg = c.orange, italic = true })
	end
	set("@lsp.typemod.variable.defaultLibrary", { fg = c.yellow })
	set("@lsp.typemod.variable.injected", { fg = c.fg })
	for _, kind in ipairs({ "FunctionDeclaration", "FunctionDefinition", "MethodDefinition", "ClassDeclaration" }) do
		set("DropBarKind" .. kind, { fg = c.muted, bg = c.bg })
		set("DropBarIconKind" .. kind, { fg = c.purple, bg = c.bg })
	end
	set("DropBarCurrentContext", { fg = c.muted, bg = c.bg })
	set("DropBarCurrentContextName", { fg = c.muted, bg = c.bg })
	set("DropBarCurrentContextIcon", { fg = c.purple, bg = c.bg })
	set("DropBarIconUISeparator", { fg = blend(c.muted, c.bg, 0.60), bg = c.bg })
	set("DropBarIconKindDefault", { fg = c.muted, bg = c.bg })
	local dropbar_kinds = {
		"Array",
		"Boolean",
		"Call",
		"Class",
		"Constant",
		"Constructor",
		"Enum",
		"EnumMember",
		"Event",
		"Field",
		"File",
		"Folder",
		"Function",
		"Interface",
		"Macro",
		"MarkdownH1",
		"MarkdownH2",
		"MarkdownH3",
		"MarkdownH4",
		"MarkdownH5",
		"MarkdownH6",
		"Method",
		"Module",
		"Namespace",
		"Package",
		"Property",
		"Struct",
		"Type",
		"Variable",
	}
	for _, kind in ipairs(dropbar_kinds) do
		set("DropBarKind" .. kind, { fg = c.muted, bg = c.bg })
		set("DropBarKind" .. kind .. "NC", { fg = c.muted, bg = c.bg })
	end
	for _, kind in ipairs({ "Function", "Method", "Class", "Struct", "Interface", "Module", "Namespace", "Type" }) do
		set("DropBarIconKind" .. kind, { fg = c.purple, bg = c.bg })
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
		vim.api.nvim_set_hl(0, "SnacksNotifierTitle" .. level, { fg = c.muted, bg = c.deep })
		vim.api.nvim_set_hl(0, "SnacksNotifierIcon" .. level, { fg = severity })
	end
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

local mode_groups = {
	n = "MayonModeBlockNormal",
	i = "MayonModeBlockInsert",
	v = "MayonModeBlockVisual",
	V = "MayonModeBlockVisual",
	["\22"] = "MayonModeBlockVisual",
	R = "MayonModeBlockReplace",
	r = "MayonModeBlockReplace",
	c = "MayonModeBlockCommand",
}

local function apply_mode()
	local mode = vim.fn.mode(1)
	local color = M.mode_color(mode)
	if color then
		vim.api.nvim_set_hl(0, "Cursor", { fg = require("mayon.generated").palette.bg, bg = color, bold = true })
		vim.api.nvim_set_hl(0, "CursorLineNr", {
			fg = color,
			bg = blend(require("mayon.generated").palette.blue, require("mayon.generated").palette.bg, 0.035),
			bold = true,
		})
	end
end

function M.mode_highlight(mode)
	local initial = tostring(mode or "n"):sub(1, 1)
	return mode_groups[mode] or mode_groups[initial] or mode_groups.n
end

function M.mode_color(mode)
	local group = M.mode_highlight(mode)
	return vim.api.nvim_get_hl(0, { name = group, link = false }).fg
end

local function active_document(win)
	if not vim.api.nvim_win_is_valid(win) then
		return false
	end
	local buf = vim.api.nvim_win_get_buf(win)
	return vim.bo[buf].buftype == "" and not vim.b[buf].snacks_dashboard
end

local function clean_document_mapping(mapping)
	local kept = {}
	for entry in mapping:gmatch("[^,]+") do
		local source, target = entry:match("^([^:]+):(.+)$")
		local stale = target
			and (
				target:match("^SnacksDashboard")
				or ((source == "Normal" or source == "NormalNC") and target == "NormalFloat")
				or (source == "WinBar" and target == "MayonPanelTitle")
				or (source == "WinSeparator" and target == "FloatBorder")
				or (source == "CursorLine" and target == "PmenuSel")
			)
		if not stale then
			kept[#kept + 1] = entry
		end
	end
	return table.concat(kept, ",")
end

local function set_cursorline_mapping(win, inactive)
	if not active_document(win) then
		return
	end
	local current = vim.wo[win].winhighlight
	if vim.api.nvim_win_get_config(win).relative == "" then
		current = clean_document_mapping(current)
		vim.wo[win].winhighlight = current
		if surface_winhighlight[win] then
			surface_winhighlight[win] = clean_document_mapping(surface_winhighlight[win])
		end
	end
	if inactive then
		if surface_winhighlight[win] then
			return
		end
		surface_winhighlight[win] = current
		local kept = {}
		for entry in current:gmatch("[^,]+") do
			if
				not entry:match("^CursorLine:")
				and not entry:match("^CursorLineNr:")
				and not entry:match("^EndOfBuffer:")
			then
				kept[#kept + 1] = entry
			end
		end
		kept[#kept + 1] = "EndOfBuffer:NormalNC"
		kept[#kept + 1] = "CursorLine:NormalNC"
		kept[#kept + 1] = "CursorLineNr:LineNr"
		vim.wo[win].winhighlight = table.concat(kept, ",")
	elseif surface_winhighlight[win] then
		vim.wo[win].winhighlight = surface_winhighlight[win]
		surface_winhighlight[win] = nil
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
			diff_add = blend(c.green, c.bg, 0.12),
			diff_delete = blend(c.red, c.bg, 0.12),
			diff_change = blend(c.blue, c.bg, 0.12),
			diff_text = blend(c.blue, c.bg, 0.18),
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
	local group = vim.api.nvim_create_augroup("MayonActiveSurface", { clear = true })
	vim.api.nvim_create_autocmd("WinLeave", {
		group = group,
		callback = function()
			set_cursorline_mapping(vim.api.nvim_get_current_win(), true)
		end,
	})
	vim.api.nvim_create_autocmd({ "WinEnter", "BufWinEnter" }, {
		group = group,
		callback = function()
			set_cursorline_mapping(vim.api.nvim_get_current_win(), false)
			apply_mode()
		end,
	})
	vim.api.nvim_create_autocmd("ModeChanged", { group = group, callback = apply_mode })
	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		callback = function(ev)
			surface_winhighlight[tonumber(ev.match)] = nil
		end,
	})
	apply_mode()
end

M.refresh = overrides

return M
