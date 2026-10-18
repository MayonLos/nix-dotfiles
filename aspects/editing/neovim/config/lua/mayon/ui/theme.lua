-- One Dark Darker owns syntax/plugin highlights; this adapter restores the
-- original Nixvim surface relationships without maintaining a second theme.
local M = {}
local configured = false

local function overrides()
	local function get(name)
		return vim.api.nvim_get_hl(0, { name = name, link = false })
	end
	local normal, comment = get("Normal"), get("Comment")
	local visual, folded, accent = get("Visual"), get("Folded"), get("Function")
	vim.api.nvim_set_hl(0, "NormalFloat", { fg = normal.fg, bg = "NONE" })
	vim.api.nvim_set_hl(0, "FloatBorder", { fg = comment.fg, bg = "NONE" })
	vim.api.nvim_set_hl(0, "FloatTitle", { fg = accent.fg, bg = "NONE", bold = true })
	vim.api.nvim_set_hl(0, "MultiCursorCursor", { fg = normal.bg, bg = accent.fg, bold = true })
	vim.api.nvim_set_hl(0, "MultiCursorDisabledCursor", { fg = normal.bg, bg = comment.fg })
	local match = get("MatchParen")
	match.bold, match.underline = true, true
	vim.api.nvim_set_hl(0, "MatchParen", match)
	vim.api.nvim_set_hl(0, "TabLine", { bg = folded.bg, fg = comment.fg })
	vim.api.nvim_set_hl(0, "TabLineSel", { bg = visual.bg, fg = normal.fg, bold = true })
	local links = {
		TreesitterContext = "NormalFloat",
		TreesitterContextSeparator = "FloatBorder",
		TreesitterContextLineNumber = "LineNr",
		SoftFloatBorder = "FloatBorder",
		WhichKeyNormal = "Normal",
		WhichKeyBorder = "FloatBorder",
		BlinkCmpMenu = "Pmenu",
		BlinkCmpMenuBorder = "FloatBorder",
		BlinkCmpMenuSelection = "PmenuSel",
		BlinkCmpDoc = "NormalFloat",
		BlinkCmpDocBorder = "FloatBorder",
		BlinkCmpSignatureHelp = "NormalFloat",
		BlinkCmpSignatureHelpBorder = "FloatBorder",
		TabLineFill = "StatusLine",
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
		MultiCursorVisual = "Visual",
		MultiCursorSign = "SignColumn",
		MultiCursorMatchPreview = "Search",
		MultiCursorDisabledVisual = "Folded",
		MultiCursorDisabledSign = "SignColumn",
		TroubleNormal = "Normal",
		TroubleNormalNC = "Normal",
	}
	for _, level in ipairs({ "Error", "Warn", "Info", "Debug", "Trace" }) do
		-- Notifications must occlude code; context headers should blend into it.
		links["SnacksNotifier" .. level] = "Normal"
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
