local M = {}

local function map(mode, lhs, rhs, desc)
	vim.keymap.set(mode, lhs, rhs, { desc = desc })
end

local function setup()
	require("nvim-surround").setup({})
	require("flash").setup({})
	require("treesitter-context").setup({
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

	-- Visual S remains nvim-surround's standard add-pair mapping.
	map({ "n", "x", "o" }, "s", function()
		require("flash").jump()
	end, "Flash jump")
	map({ "n", "o" }, "S", function()
		require("flash").treesitter()
	end, "Flash treesitter select")
	map("o", "r", function()
		require("flash").remote()
	end, "Remote flash")
	map({ "o", "x" }, "R", function()
		require("flash").treesitter_search()
	end, "Treesitter search")
	map("n", "[c", function()
		require("treesitter-context").go_to_context(vim.v.count1)
	end, "Jump to context (upwards)")

	local select = require("nvim-treesitter-textobjects.select").select_textobject
	local move = require("nvim-treesitter-textobjects.move")
	for _, spec in ipairs({
		{ "af", "@function.outer", "Select function (outer)" },
		{ "if", "@function.inner", "Select function (inner)" },
		{ "ac", "@class.outer", "Select class (outer)" },
		{ "ic", "@class.inner", "Select class (inner)" },
		{ "aa", "@parameter.outer", "Select parameter (outer)" },
		{ "ia", "@parameter.inner", "Select parameter (inner)" },
		{ "al", "@loop.outer", "Select loop (outer)" },
		{ "il", "@loop.inner", "Select loop (inner)" },
		{ "ai", "@conditional.outer", "Select conditional (outer)" },
		{ "ii", "@conditional.inner", "Select conditional (inner)" },
	}) do
		map({ "x", "o" }, spec[1], function()
			select(spec[2], "textobjects")
		end, spec[3])
	end
	for _, spec in ipairs({
		{ "]m", move.goto_next_start, "@function.outer", "Next function start" },
		{ "[m", move.goto_previous_start, "@function.outer", "Prev function start" },
		{ "]M", move.goto_next_end, "@function.outer", "Next function end" },
		{ "[M", move.goto_previous_end, "@function.outer", "Prev function end" },
		{ "]]", move.goto_next_start, "@class.outer", "Next class start" },
		{ "[[", move.goto_previous_start, "@class.outer", "Prev class start" },
	}) do
		map({ "n", "x", "o" }, spec[1], function()
			spec[2](spec[3], "textobjects")
		end, spec[4])
	end
	map("n", "<leader>sn", function()
		require("nvim-treesitter-textobjects.swap").swap_next("@parameter.inner")
	end, "Swap parameter with next")
	map("n", "<leader>sp", function()
		require("nvim-treesitter-textobjects.swap").swap_previous("@parameter.inner")
	end, "Swap parameter with prev")

	local mc = require("multicursor-nvim")
	-- These bindings only exist while multiple cursors are active.
	mc.addKeymapLayer(function(layer)
		layer({ "n", "x" }, "<left>", mc.prevCursor, { desc = "Previous cursor" })
		layer({ "n", "x" }, "<right>", mc.nextCursor, { desc = "Next cursor" })
		layer({ "n", "x" }, "<leader>mx", mc.deleteCursor, { desc = "Delete main cursor" })
		layer("n", "<esc>", function()
			if mc.cursorsEnabled() then
				mc.clearCursors()
			else
				mc.enableCursors()
			end
		end, { desc = "Clear cursors" })
	end)
	local actions = {
		n = {
			function()
				mc.matchAddCursor(1)
			end,
			"Add cursor at next match",
		},
		N = {
			function()
				mc.matchAddCursor(-1)
			end,
			"Add cursor at previous match",
		},
		s = {
			function()
				mc.matchSkipCursor(1)
			end,
			"Skip next match",
		},
		S = {
			function()
				mc.matchSkipCursor(-1)
			end,
			"Skip previous match",
		},
		j = {
			function()
				mc.lineAddCursor(1)
			end,
			"Add cursor on line below",
		},
		k = {
			function()
				mc.lineAddCursor(-1)
			end,
			"Add cursor on line above",
		},
		a = { mc.matchAllAddCursors, "Add cursor to every match" },
		t = { mc.toggleCursor, "Disable / re-enable cursors" },
		q = { mc.clearCursors, "Clear cursors" },
		g = { mc.addCursorOperator, "Add cursor over motion" },
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
			require("nvim-autopairs").setup({})
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
