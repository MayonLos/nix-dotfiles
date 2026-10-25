local M = {}

local function map(mode, lhs, rhs, desc)
	vim.keymap.set(mode, lhs, rhs, { desc = desc })
end

local function setup()
	require("nvim-surround").setup({})
	require("flash").setup({})
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
	require("nvim-treesitter-textobjects").setup({
		select = { lookahead = true },
		move = { set_jumps = true },
	})
	require("multicursor-nvim").setup()

	map({ "n", "o" }, "s", function()
		require("flash").jump()
	end, "Jump with Flash")
	map("n", "[c", function()
		require("treesitter-context").go_to_context(vim.v.count1)
	end, "Jump to Parent Syntax")

	local select = require("nvim-treesitter-textobjects.select").select_textobject
	local move = require("nvim-treesitter-textobjects.move")
	for _, spec in ipairs({
		{ "af", "@function.outer", "Select Outer Function" },
		{ "if", "@function.inner", "Select Inner Function" },
		{ "ac", "@class.outer", "Select Outer Class" },
		{ "ic", "@class.inner", "Select Inner Class" },
		{ "aa", "@parameter.outer", "Select Outer Parameter" },
		{ "ia", "@parameter.inner", "Select Inner Parameter" },
		{ "al", "@loop.outer", "Select Outer Loop" },
		{ "il", "@loop.inner", "Select Inner Loop" },
		{ "ai", "@conditional.outer", "Select Outer Conditional" },
		{ "ii", "@conditional.inner", "Select Inner Conditional" },
	}) do
		map({ "x", "o" }, spec[1], function()
			select(spec[2], "textobjects")
		end, spec[3])
	end
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

	local mc = require("multicursor-nvim")
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

return {
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
				"multicursor.nvim",
			}) do
				require("mayon.config.loader").pack(n)
			end
		end,
		after = setup,
	},
}
