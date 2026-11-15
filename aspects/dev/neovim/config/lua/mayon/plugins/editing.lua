local M = {}

local function map(mode, lhs, rhs, desc)
	vim.keymap.set(mode, lhs, rhs, { desc = desc })
end

local function setup_surround()
	require("nvim-surround").setup({})
end

local function setup_flash()
	require("flash").setup({})
	map({ "n", "o" }, "s", function()
		require("flash").jump()
	end, "Jump with Flash")
end

local function setup_context()
	require("treesitter-context").setup({
		enable = false,
		max_lines = 3,
		multiline_threshold = 1,
		trim_scope = "outer",
		mode = "cursor",
		on_attach = function(buf)
			return not vim.tbl_contains({ "markdown", "codecompanion" }, vim.bo[buf].filetype)
		end,
		zindex = 20,
	})
	map("n", "[c", function()
		require("treesitter-context").go_to_context(vim.v.count1)
	end, "Jump to Parent Syntax")
end

local function setup_textobjects()
	require("nvim-treesitter-textobjects").setup({
		select = { lookahead = true },
		move = { set_jumps = true },
	})
	-- Selection belongs to mini.ai (see setup_ai); this plugin keeps the
	-- query files plus the motions and swaps below.
	local move = require("nvim-treesitter-textobjects.move")
	for _, spec in ipairs({
		{ "]m", move.goto_next_start, "@function.outer", "Jump to Next Function Start" },
		{ "[m", move.goto_previous_start, "@function.outer", "Jump to Prev Function Start" },
		{ "]M", move.goto_next_end, "@function.outer", "Jump to Next Function End" },
		{ "[M", move.goto_previous_end, "@function.outer", "Jump to Prev Function End" },
		{ "]]", move.goto_next_start, "@class.outer", "Jump to Next Class Start" },
		{ "[[", move.goto_previous_start, "@class.outer", "Jump to Prev Class Start" },
	}) do
		map({ "n", "x", "o" }, spec[1], function()
			spec[2](spec[3], "textobjects")
		end, spec[4])
	end
	map("n", "<leader>c]", function()
		require("nvim-treesitter-textobjects.swap").swap_next("@parameter.inner")
	end, "Swap Parameter with Next")
	map("n", "<leader>c[", function()
		require("nvim-treesitter-textobjects.swap").swap_previous("@parameter.inner")
	end, "Swap Parameter with Prev")
end

-- mini.ai owns every a/i textobject. Tree-sitter queries keep the previous
-- f/c/l/i meanings; mini.ai's own `a` (argument) matches the old query result
-- and also works without a parser. It adds q (quote), b (bracket), t (tag),
-- F (call), g (buffer) and count/next-search on all of them. Next/last use
-- aN/aL so al/il stay loops and Neovim's an/in node selection is untouched.
local function setup_ai()
	local ai = require("mini.ai")
	local ts = ai.gen_spec.treesitter
	ai.setup({
		n_lines = 500,
		custom_textobjects = {
			f = ts({ a = "@function.outer", i = "@function.inner" }),
			c = ts({ a = "@class.outer", i = "@class.inner" }),
			l = ts({ a = "@loop.outer", i = "@loop.inner" }),
			i = ts({ a = "@conditional.outer", i = "@conditional.inner" }),
			F = ai.gen_spec.function_call(),
			g = function()
				local last = vim.fn.line("$")
				return { from = { line = 1, col = 1 }, to = { line = last, col = math.max(#vim.fn.getline(last), 1) } }
			end,
		},
		mappings = { around_next = "aN", inside_next = "iN", around_last = "aL", inside_last = "iL" },
	})
end

local function setup_multicursor()
	local mc = require("multicursor-nvim")
	mc.setup()
	-- These bindings only exist while multiple cursors are active.
	mc.addKeymapLayer(function(layer)
		layer({ "n", "x" }, "<left>", mc.prevCursor, { desc = "Move to Prev Cursor" })
		layer({ "n", "x" }, "<right>", mc.nextCursor, { desc = "Move to Next Cursor" })
		layer({ "n", "x" }, "<leader>mx", mc.deleteCursor, { desc = "Remove Main Cursor" })
		layer("n", "<esc>", function()
			if mc.cursorsEnabled() then
				mc.clearCursors()
			else
				mc.enableCursors()
			end
		end, { desc = "Clear Multicursor" })
	end)
	local actions = {
		n = {
			function()
				mc.matchAddCursor(1)
			end,
			"Add Cursor at Next Match",
		},
		N = {
			function()
				mc.matchAddCursor(-1)
			end,
			"Add Cursor at Prev Match",
		},
		s = {
			function()
				mc.matchSkipCursor(1)
			end,
			"Skip Next Match",
		},
		S = {
			function()
				mc.matchSkipCursor(-1)
			end,
			"Skip Prev Match",
		},
		j = {
			function()
				mc.lineAddCursor(1)
			end,
			"Add Cursor to Next Line",
		},
		k = {
			function()
				mc.lineAddCursor(-1)
			end,
			"Add Cursor to Prev Line",
		},
		a = { mc.matchAllAddCursors, "Add Cursors to All Matches" },
		t = { mc.toggleCursor, "Toggle Multicursor" },
		q = { mc.clearCursors, "Clear Multicursor" },
		g = { mc.addCursorOperator, "Add Cursor with Operator" },
	}
	for key, action in pairs(actions) do
		map({ "n", "x" }, "<leader>m" .. key, action[1], action[2])
	end
end

local function setup_dial()
	local augend = require("dial.augend")
	require("dial.config").augends:register_group({
		default = {
			augend.integer.alias.decimal_int,
			augend.integer.alias.hex,
			augend.date.alias["%Y-%m-%d"],
			augend.date.alias["%Y/%m/%d"],
			augend.constant.alias.bool,
			augend.constant.alias.Bool,
			augend.semver.alias.semver,
			augend.constant.new({ elements = { "&&", "||" }, word = false, cyclic = true }),
			augend.constant.new({ elements = { "and", "or" } }),
			augend.constant.new({ elements = { "yes", "no" } }),
			augend.constant.new({ elements = { "on", "off" } }),
			augend.misc.alias.markdown_header,
		},
	})
end

-- Ctrl+a/x keep their builtin meaning, extended to booleans, dates, versions,
-- operators and Markdown headings. g-variants increment progressively.
local function dial(direction, mode)
	return function()
		require("dial.map").manipulate(direction, mode)
	end
end

local function setup()
	setup_surround()
	setup_flash()
	setup_context()
	setup_textobjects()
	setup_ai()
	setup_multicursor()
end

return {
	{
		"dial.nvim",
		keys = {
			{ "<C-a>", dial("increment", "normal"), desc = "Increment" },
			{ "<C-x>", dial("decrement", "normal"), desc = "Decrement" },
			{ "g<C-a>", dial("increment", "gnormal"), desc = "Increment Progressively" },
			{ "g<C-x>", dial("decrement", "gnormal"), desc = "Decrement Progressively" },
			{ "<C-a>", dial("increment", "visual"), desc = "Increment", mode = "x" },
			{ "<C-x>", dial("decrement", "visual"), desc = "Decrement", mode = "x" },
			{ "g<C-a>", dial("increment", "gvisual"), desc = "Increment Progressively", mode = "x" },
			{ "g<C-x>", dial("decrement", "gvisual"), desc = "Decrement Progressively", mode = "x" },
		},
		after = setup_dial,
	},
	{
		"nvim-autopairs",
		event = "InsertEnter",
		after = function()
			require("nvim-autopairs").setup({ map_cr = false })
		end,
	},
	{
		"flash.nvim",
		event = { "BufReadPre", "BufNewFile" },
		before = function()
			for _, n in ipairs({
				"nvim-surround",
				"nvim-treesitter-context",
				"nvim-treesitter-textobjects",
				"mini.ai",
				"multicursor.nvim",
			}) do
				require("mayon.config.loader").pack(n)
			end
		end,
		after = setup,
	},
}
