-- Layout skeleton: Edgy side/bottom panels, smart-splits, and the AI panel
-- width fit. The AI-terminal predicate and winbar render live in one place.
-- smart-splits reads this global before its module is loaded and marks the
-- active tmux pane as a Neovim pane for the companion tmux bindings.
vim.g.smart_splits_multiplexer_integration = vim.env.TMUX and "tmux" or false

local ai_panels = require("mayon.ui.ai_panels")
local util = require("mayon.util")

local function wide_enough(_, win)
	return util.wide() and vim.api.nvim_win_get_config(win).relative == ""
end

-- Single owner of the AI side panel width; Edgy and the resize fit share it.
local function ai_panel_width()
	return math.max(36, math.floor(vim.o.columns * 0.38))
end

-- Edgy sizes its windows when they open. Panels keep winfixwidth, so a later
-- terminal resize (e.g. Mango tiling kitty to half width) would squeeze the
-- document window to a single column. Re-apply the proportional width.
local function fit_ai_panels()
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local buf = vim.api.nvim_win_get_buf(win)
		if vim.api.nvim_win_get_config(win).relative == "" and ai_panels.is_panel(buf) then
			vim.api.nvim_win_set_width(win, ai_panel_width())
		end
	end
end

-- Bottom panel winbar: clickable Terminal/Problems/Git/Tasks capsules plus the
-- current panel title. Inlined here because Edgy is its only caller.
local bottom_labels = { "Terminal", "Problems", "Git", "Tasks" }
local bottom_actions = { "terminal", "problems", "commit", "tasks" }

local function bottom_click(id)
	vim.schedule(function()
		require("mayon.ui.workspace").action(bottom_actions[id])
	end)
end

local function bottom_render()
	local win = tonumber(vim.g.statusline_winid) or 0
	local buf = vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) or 0
	local ft = vim.bo[buf].filetype
	local active = (ft == "trouble" or ft == "qf") and 2 or ft:match("git") and 3 or 1
	local parts = { " " }
	for i, label in ipairs(bottom_labels) do
		parts[#parts + 1] = (i == active and "%#TabLineSel#" or "%#TabLine#")
			.. "%"
			.. i
			.. "@v:lua.MayonBottomClick@ "
			.. label
			.. " %X  "
	end
	return table.concat(parts)
		.. "%=%#MayonPanelTitle# "
		.. (ft == "qf" and "Quickfix" or ft == "trouble" and "Diagnostics" or "Terminal")
		.. " · Workspace "
end

local function setup_edgy()
	-- The bottom winbar is invoked via statusline syntax; expose its renderer
	-- and click handler as globals, matching the other winbar entry points.
	vim.opt.splitkeep = "screen"
	_G.MayonBottomClick = bottom_click
	_G.MayonBottomWinbar = bottom_render
	local bottom_winbar = "%!v:lua.MayonBottomWinbar()"
	local palette = util.palette()
	vim.api.nvim_set_hl(0, "EdgyNormal", { fg = palette.brightFg, bg = palette.bg })
	vim.api.nvim_set_hl(0, "EdgyWinBar", { fg = palette.blue, bg = palette.bg, bold = true })
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
			},
			{
				ft = "snacks_terminal",
				title = "AI CLI",
				wo = {
					winbar = ai_winbar,
					winhighlight = "WinBar:EdgyWinBar,Normal:EdgyNormal",
					signcolumn = "yes:1",
					fillchars = "eob: ",
				},
				filter = function(buf, win)
					return wide_enough(buf, win) and ai_panels.is_ai_terminal(buf)
				end,
			},
		},
		bottom = {
			{
				ft = "trouble",
				title = "Diagnostics",
				size = { height = 12 },
				wo = { winbar = bottom_winbar },
			},
			{
				ft = "qf",
				title = "Quickfix",
				size = { height = 10 },
				wo = { winbar = bottom_winbar },
			},
			{
				ft = "snacks_terminal",
				title = "Terminal",
				filter = function(buf, win)
					return not ai_panels.is_ai_terminal(buf) and vim.api.nvim_win_get_config(win).relative == ""
				end,
				size = { height = 14 },
				wo = { winbar = bottom_winbar },
			},
		},
		options = {
			left = {
				size = function()
					return math.min(30, math.max(22, math.floor(vim.o.columns * 0.28)))
				end,
			},
			right = { size = ai_panel_width },
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
	vim.api.nvim_create_autocmd({ "VimResized", "TabEnter" }, {
		group = vim.api.nvim_create_augroup("MayonAIPanelWidth", { clear = true }),
		callback = fit_ai_panels,
	})
end

local function setup_smart_splits()
	local splits = require("smart-splits")
	splits.setup({ at_edge = "stop" })
	for _, spec in ipairs({
		{ "<C-h>", splits.move_cursor_left, "Focus Left Window or Tmux" },
		{ "<C-j>", splits.move_cursor_down, "Focus Lower Window or Tmux" },
		{ "<C-k>", splits.move_cursor_up, "Focus Upper Window or Tmux" },
		{ "<C-l>", splits.move_cursor_right, "Focus Right Window or Tmux" },
		{ "<A-h>", splits.resize_left, "Resize Window Left" },
		{ "<A-j>", splits.resize_down, "Resize Window Down" },
		{ "<A-k>", splits.resize_up, "Resize Window Up" },
		{ "<A-l>", splits.resize_right, "Resize Window Right" },
	}) do
		vim.keymap.set("n", spec[1], spec[2], { desc = spec[3], silent = true })
	end
end

local smart_split_keys = {
	{ "<C-h>", desc = "Focus Left Window or Tmux" },
	{ "<C-j>", desc = "Focus Lower Window or Tmux" },
	{ "<C-k>", desc = "Focus Upper Window or Tmux" },
	{ "<C-l>", desc = "Focus Right Window or Tmux" },
	{ "<A-h>", desc = "Resize Window Left" },
	{ "<A-j>", desc = "Resize Window Down" },
	{ "<A-k>", desc = "Resize Window Up" },
	{ "<A-l>", desc = "Resize Window Right" },
}

return {
	{
		"aerial.nvim",
		event = { "BufReadPost", "BufNewFile" },
		after = function()
			local outline = require("mayon.ui.outline")
			require("aerial").setup({
				-- lz.n already deferred the plugin until a document exists.
				lazy_load = false,
				layout = {
					default_direction = "right",
					placement = "edge",
					min_width = 26,
					max_width = 30,
					resize_to_content = false,
				},
				attach_mode = "window",
				close_automatic_events = {},
				show_guides = false,
				filter_kind = false,
				highlight_mode = "full_width",
				highlight_closest = true,
				-- The workbench owns opening; the outline is manual-only.
				open_automatic = false,
			})
			outline.setup()
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
