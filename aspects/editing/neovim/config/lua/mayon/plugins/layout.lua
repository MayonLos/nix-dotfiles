-- smart-splits reads this global before its module is loaded and marks the
-- active tmux pane as a Neovim pane for the companion tmux bindings.
vim.g.smart_splits_multiplexer_integration = vim.env.TMUX and "tmux" or false

local function wide_enough()
	return vim.o.columns >= 90
end

local function is_explorer_buffer(buf)
	local ok, pickers = pcall(function()
		return require("snacks").picker.get({ source = "explorer" })
	end)
	if not ok then
		return false
	end
	for _, picker in ipairs(pickers) do
		local list = picker.list
		if list and list.win and list.win.buf == buf then
			return true
		end
	end
	return false
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
	vim.opt.laststatus = 3
	vim.opt.splitkeep = "screen"
	local palette = require("mayon.generated").palette
	vim.api.nvim_set_hl(0, "EdgyNormal", { fg = palette.fg, bg = palette.surface })
	vim.api.nvim_set_hl(0, "EdgyWinBar", { fg = palette.cyan, bg = palette.surface, bold = true })
	require("edgy").setup({
		left = {
			{
				ft = "snacks_picker_list",
				title = "文件树",
				filter = function(buf)
					return wide_enough() and is_explorer_buffer(buf)
				end,
				size = { width = 30 },
			},
		},
		right = {
			{
				ft = "claudecode",
				title = "Claude Code",
				filter = function()
					return wide_enough()
				end,
				size = { width = 42 },
			},
			{
				ft = "codecompanion",
				title = "CodeCompanion",
				filter = function()
					return wide_enough()
				end,
				size = { width = 42 },
			},
			{
				ft = "snacks_terminal",
				title = "AI 命令行",
				filter = function(buf)
					return wide_enough() and is_ai_terminal(buf)
				end,
				size = { width = 42 },
			},
			{
				ft = "sidekick_terminal",
				title = "Sidekick AI",
				filter = function()
					return wide_enough()
				end,
				size = { width = 42 },
			},
		},
		bottom = {
			{ ft = "trouble", title = "问题与诊断", size = { height = 12 } },
			{ ft = "qf", title = "快速修复与位置列表", size = { height = 10 } },
			{
				ft = "snacks_terminal",
				title = "终端",
				filter = function(buf)
					return not is_ai_terminal(buf)
				end,
				size = { height = 14 },
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
					return math.min(42, math.max(30, math.floor(vim.o.columns * 0.36)))
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
	{ "edgy.nvim", event = "User MayonVeryLazy", after = setup_edgy },
	{
		"smart-splits.nvim",
		keys = smart_split_keys,
		event = "User MayonVeryLazy",
		after = setup_smart_splits,
	},
}
