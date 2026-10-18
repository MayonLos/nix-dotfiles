-- One Dark Darker owns syntax/plugin highlights; this adapter restores the
-- editor surfaces without maintaining a second syntax theme.
local M = {}
local configured = false

local function overrides()
	local function get(name)
		return vim.api.nvim_get_hl(0, { name = name, link = false })
	end
	local c = require("mayon.generated").palette
	local normal, comment = get("Normal"), get("Comment")
	local function set(name, values)
		vim.api.nvim_set_hl(0, name, values)
	end
	local function tint(base, accent, amount)
		local out = "#"
		for i = 2, 6, 2 do
			local a, b = tonumber(base:sub(i, i + 1), 16), tonumber(accent:sub(i, i + 1), 16)
			out = out .. string.format("%02x", math.floor(a + (b - a) * amount + 0.5))
		end
		return out
	end
	set("StatusLine", { fg = c.fg, bg = c.deep })
	set("StatusLineNC", { fg = c.muted, bg = c.deep })
	set("MayonProject", { fg = c.blue, bg = c.deep, bold = true })
	set("MayonPosition", { fg = c.blue, bg = c.surface, bold = true })
	set("MayonTabAccent", { fg = c.blue, bg = c.surface })
	set("MayonTabVisible", { fg = c.fg, bg = c.bg, bold = true })
	set("MayonSidebar", { fg = c.fg, bg = c.deep })
	set("MayonSidebarLine", { fg = c.brightFg, bg = c.selection, bold = true })
	set("MayonMuted", { fg = c.muted })
	local accent = get("Function")
	vim.api.nvim_set_hl(0, "NormalFloat", { fg = normal.fg, bg = c.deep })
	vim.api.nvim_set_hl(0, "FloatBorder", { fg = c.border, bg = c.deep })
	vim.api.nvim_set_hl(0, "FloatTitle", { fg = c.blue, bg = c.deep, bold = true })
	vim.api.nvim_set_hl(0, "MultiCursorCursor", { fg = normal.bg, bg = accent.fg, bold = true })
	vim.api.nvim_set_hl(0, "MultiCursorDisabledCursor", { fg = normal.bg, bg = comment.fg })
	local match = get("MatchParen")
	match.bold, match.underline = true, true
	vim.api.nvim_set_hl(0, "MatchParen", match)
	set("TabLine", { bg = c.bg, fg = c.muted })
	set("TabLineSel", { bg = c.surface, fg = c.brightFg, bold = true, underline = true, sp = c.blue })
	set("TabLineFill", { bg = c.bg, fg = c.muted })
	set("TreesitterContext", { bg = c.surface })
	set("TreesitterContextLineNumber", { bg = c.surface, fg = c.muted })
	set("TreesitterContextSeparator", { fg = c.border, bg = c.surface })
	set("Pmenu", { fg = c.fg, bg = c.deep })
	set("PmenuSel", { fg = c.brightFg, bg = tint(c.surface, c.blue, 0.14), bold = true })
	set("BlinkCmpLabel", { fg = c.brightFg })
	set("BlinkCmpLabelMatch", { fg = c.cyan, bold = true })
	set("BlinkCmpLabelDetail", { fg = c.muted })
	set("BlinkCmpLabelDescription", { fg = c.muted })
	set("BlinkCmpSource", { fg = c.muted, italic = true })
	set("BlinkCmpGhostText", { fg = c.border, italic = true })
	for level, color in ipairs({ c.blue, c.cyan, c.fg, c.fg, c.muted, c.muted }) do
		set("RenderMarkdownH" .. level, { fg = color, bold = true })
		-- Render-markdown owns the icon/background; Tree-sitter owns heading text.
		set("@markup.heading." .. level .. ".markdown", { link = "RenderMarkdownH" .. level })
		set("markdownH" .. level, { link = "RenderMarkdownH" .. level })
		set("RenderMarkdownH" .. level .. "Bg", { bg = level == 1 and tint(c.bg, c.blue, 0.10) or c.bg })
	end
	set("RenderMarkdownCode", { bg = c.deep })
	set("RenderMarkdownCodeInline", { fg = c.cyan, bg = c.surface })
	set("RenderMarkdownCodeBorder", { fg = c.deep, bg = c.bg })
	set("RenderMarkdownTableHead", { fg = c.cyan, bold = true })
	set("@markup.heading.markdown", { link = "RenderMarkdownTableHead" })
	set("RenderMarkdownTableRow", { fg = c.border })
	set("RenderMarkdownTableFill", { bg = c.bg })
	set("RenderMarkdownBullet", { fg = c.cyan })
	set("RenderMarkdownQuote", { fg = c.cyan })
	set("RenderMarkdownDash", { fg = c.border })
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
		SnacksPickerList = "MayonSidebar",
		SnacksPickerBorder = "FloatBorder",
		SnacksPickerTitle = "FloatTitle",
		SnacksPickerInput = "NormalFloat",
		SnacksPickerInputBorder = "FloatBorder",
		SnacksPickerBoxBorder = "FloatBorder",
		SnacksPickerListCursorLine = "MayonSidebarLine",
		SnacksPickerPreviewCursorLine = "CursorLine",
		SnacksPickerDirectory = "Directory",
		SnacksPickerTree = "Comment",
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
		-- The same opaque surface backs menus, notifications and input prompts.
		links["SnacksNotifier" .. level] = "NormalFloat"
		links["SnacksNotifierBorder" .. level] = "FloatBorder"
	end
	for name in pairs(vim.api.nvim_get_hl(0, {})) do
		if name:match("^NoiceCmdlinePopupBorder") then
			links[name] = "FloatBorder"
		end
	end
	for name, target in pairs(links) do
		vim.api.nvim_set_hl(0, name, { link = target })
	end
	vim.api.nvim_set_hl(0, "FzfLuaSurface", { fg = normal.fg, bg = normal.bg })
	vim.api.nvim_set_hl(0, "FzfLuaSurfaceBorder", { fg = comment.fg, bg = normal.bg })
	vim.api.nvim_set_hl(0, "FzfLuaSurfaceTitle", { fg = accent.fg, bg = normal.bg, bold = true })
	for _, name in ipairs({
		"FzfLuaBorder",
		"FzfLuaPreviewBorder",
		"FzfLuaFzfBorder",
		"FzfLuaFzfSeparator",
		"FzfLuaScrollBorderEmpty",
		"FzfLuaScrollBorderFull",
	}) do
		vim.api.nvim_set_hl(0, name, { link = "FzfLuaSurfaceBorder" })
	end
	for _, name in ipairs({ "FzfLuaNormal", "FzfLuaPreviewNormal", "FzfLuaFzfNormal", "FzfLuaFzfGutter" }) do
		vim.api.nvim_set_hl(0, name, { link = "FzfLuaSurface" })
	end
	for _, name in ipairs({ "FzfLuaTitle", "FzfLuaPreviewTitle" }) do
		vim.api.nvim_set_hl(0, name, { link = "FzfLuaSurfaceTitle" })
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
			bg_d = c.deep,
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

return M
