-- smart-splits reads this global before its module is loaded and marks the
-- active tmux pane as a Neovim pane for the companion tmux bindings.
vim.g.smart_splits_multiplexer_integration = vim.env.TMUX and "tmux" or false

local function wide_enough(_, win)
	return vim.o.columns >= 120 and vim.api.nvim_win_get_config(win).relative == ""
end

local function terminal_command(buf)
	local terminal = vim.b[buf].snacks_terminal
	local cmd = terminal and terminal.cmd
	if type(cmd) == "table" then
		return table.concat(cmd, " "):lower()
	end
	return type(cmd) == "string" and cmd:lower() or ""
end

local function is_ai_terminal(buf)
	local filetype = vim.bo[buf].filetype
	local cmd = terminal_command(buf)
	return filetype == "sidekick_terminal"
		or filetype == "sidekick"
		or cmd:match("claude") ~= nil
		or cmd:match("codex") ~= nil
		or cmd:match("grok") ~= nil
end

local function setup_edgy()
	require("mayon.ui.bottom").setup()
	vim.opt.laststatus = 3
	vim.opt.splitkeep = "screen"
	local palette = require("mayon.generated").palette
	vim.api.nvim_set_hl(0, "EdgyNormal", { fg = palette.brightFg, bg = palette.bg })
	vim.api.nvim_set_hl(0, "EdgyWinBar", { fg = palette.blue, bg = palette.deep, bold = true })
	local ai_winbar = "%!v:lua.require'mayon.ui.ai_panels'.winbar()"
	require("edgy").setup({
		right = {
			{
				ft = "claudecode",
				title = "Claude Code",
				wo = {
					winbar = ai_winbar,
					winhighlight = "WinBar:EdgyWinBar,Normal:EdgyNormal",
					signcolumn = "yes:1",
					fillchars = "eob: ",
				},
				filter = wide_enough,
				size = { width = 0.38 },
			},
			{
				ft = "codecompanion",
				title = "CodeCompanion",
				wo = {
					winbar = ai_winbar,
					winhighlight = "WinBar:EdgyWinBar,Normal:EdgyNormal",
					signcolumn = "yes:1",
					fillchars = "eob: ",
				},
				filter = wide_enough,
				size = { width = 0.38 },
			},
			{
				ft = "snacks_terminal",
				title = "AI 命令行",
				wo = {
					winbar = ai_winbar,
					winhighlight = "WinBar:EdgyWinBar,Normal:EdgyNormal",
					signcolumn = "yes:1",
					fillchars = "eob: ",
				},
				filter = function(buf, win)
					return wide_enough(buf, win) and is_ai_terminal(buf)
				end,
				size = { width = 0.38 },
			},
			{
				ft = "sidekick_terminal",
				title = "Sidekick AI",
				wo = {
					winbar = ai_winbar,
					winhighlight = "WinBar:EdgyWinBar,Normal:EdgyNormal",
					signcolumn = "yes:1",
					fillchars = "eob: ",
				},
				filter = wide_enough,
				size = { width = 0.38 },
			},
		},
		bottom = {
			{
				ft = "trouble",
				title = "诊断",
				size = { height = 12 },
				wo = { winbar = "%!v:lua.require'mayon.ui.bottom'.render()" },
			},
			{
				ft = "qf",
				title = "快速修复",
				size = { height = 10 },
				wo = { winbar = "%!v:lua.require'mayon.ui.bottom'.render()" },
			},
			{
				ft = "snacks_terminal",
				title = "终端",
				filter = function(buf, win)
					return not is_ai_terminal(buf) and vim.api.nvim_win_get_config(win).relative == ""
				end,
				size = { height = 14 },
				wo = { winbar = "%!v:lua.require'mayon.ui.bottom'.render()" },
			},
		},
		options = {
			left = {
				size = function()
					return math.min(30, math.max(22, math.floor(vim.o.columns * 0.28)))
				end,
			},
			right = {
				size = function()
					return math.max(36, math.floor(vim.o.columns * 0.38))
				end,
			},
			bottom = { size = 12 },
		},
		animate = { enabled = false },
		wo = {
			winbar = true,
			winfixwidth = true,
			winhighlight = "WinBar:EdgyWinBar,Normal:EdgyNormal",
			spell = false,
			signcolumn = "no",
		},
	})
end

local function setup_smart_splits()
	local splits = require("smart-splits")
	splits.setup({ at_edge = "stop" })
	for _, spec in ipairs({
		{ "<C-h>", splits.move_cursor_left, "移到左侧窗口或 tmux 面板" },
		{ "<C-j>", splits.move_cursor_down, "移到下方窗口或 tmux 面板" },
		{ "<C-k>", splits.move_cursor_up, "移到上方窗口或 tmux 面板" },
		{ "<C-l>", splits.move_cursor_right, "移到右侧窗口或 tmux 面板" },
		{ "<A-h>", splits.resize_left, "向左调整窗口大小" },
		{ "<A-j>", splits.resize_down, "向下调整窗口大小" },
		{ "<A-k>", splits.resize_up, "向上调整窗口大小" },
		{ "<A-l>", splits.resize_right, "向右调整窗口大小" },
	}) do
		vim.keymap.set("n", spec[1], spec[2], { desc = spec[3], silent = true })
	end
end

local smart_split_keys = {
	{ "<C-h>", desc = "移到左侧窗口或 tmux 面板" },
	{ "<C-j>", desc = "移到下方窗口或 tmux 面板" },
	{ "<C-k>", desc = "移到上方窗口或 tmux 面板" },
	{ "<C-l>", desc = "移到右侧窗口或 tmux 面板" },
	{ "<A-h>", desc = "向左调整窗口大小" },
	{ "<A-j>", desc = "向下调整窗口大小" },
	{ "<A-k>", desc = "向上调整窗口大小" },
	{ "<A-l>", desc = "向右调整窗口大小" },
}

return {
	{
		"dropbar.nvim",
		event = { "BufReadPost", "BufNewFile" },
		after = function()
			require("mayon.ui.breadcrumbs").setup()
		end,
	},
	{
		"aerial.nvim",
		cmd = { "AerialToggle", "AerialOpen", "AerialClose" },
		after = function()
			require("aerial").setup({
				layout = { default_direction = "left", min_width = 28 },
				attach_mode = "global",
				show_guides = false,
				filter_kind = false,
			})
		end,
	},
	{ "edgy.nvim", event = "User MayonVeryLazy", after = setup_edgy },
	{
		"smart-splits.nvim",
		keys = smart_split_keys,
		event = "User MayonVeryLazy",
		after = setup_smart_splits,
	},
}
