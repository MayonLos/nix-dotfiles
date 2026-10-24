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
	end, "Flash 跳转")
	map("n", "[h", function()
		require("gitsigns").nav_hunk("prev")
	end, "上一个 Git 修改块")
	map("n", "]h", function()
		require("gitsigns").nav_hunk("next")
	end, "下一个 Git 修改块")
	map("n", "[c", function()
		require("treesitter-context").go_to_context(vim.v.count1)
	end, "跳到上层语法上下文")

	local select = require("nvim-treesitter-textobjects.select").select_textobject
	local move = require("nvim-treesitter-textobjects.move")
	for _, spec in ipairs({
		{ "af", "@function.outer", "选择整个函数" },
		{ "if", "@function.inner", "选择函数内容" },
		{ "ac", "@class.outer", "选择整个类" },
		{ "ic", "@class.inner", "选择类内容" },
		{ "aa", "@parameter.outer", "选择整个参数" },
		{ "ia", "@parameter.inner", "选择参数内容" },
		{ "al", "@loop.outer", "选择整个循环" },
		{ "il", "@loop.inner", "选择循环内容" },
		{ "ai", "@conditional.outer", "选择整个条件块" },
		{ "ii", "@conditional.inner", "选择条件块内容" },
	}) do
		map({ "x", "o" }, spec[1], function()
			select(spec[2], "textobjects")
		end, spec[3])
	end
	for _, spec in ipairs({
		{ "]m", move.goto_next_start, "@function.outer", "下一个函数开头" },
		{ "[m", move.goto_previous_start, "@function.outer", "上一个函数开头" },
		{ "]M", move.goto_next_end, "@function.outer", "下一个函数结尾" },
		{ "[M", move.goto_previous_end, "@function.outer", "上一个函数结尾" },
		{ "]]", move.goto_next_start, "@class.outer", "下一个类开头" },
		{ "[[", move.goto_previous_start, "@class.outer", "上一个类开头" },
	}) do
		map({ "n", "x", "o" }, spec[1], function()
			spec[2](spec[3], "textobjects")
		end, spec[4])
	end
	map("n", "<leader>c]", function()
		require("nvim-treesitter-textobjects.swap").swap_next("@parameter.inner")
	end, "将参数与下一个交换")
	map("n", "<leader>c[", function()
		require("nvim-treesitter-textobjects.swap").swap_previous("@parameter.inner")
	end, "将参数与上一个交换")

	local mc = require("multicursor-nvim")
	-- These bindings only exist while multiple cursors are active.
	mc.addKeymapLayer(function(layer)
		layer({ "n", "x" }, "<left>", mc.prevCursor, { desc = "上一个光标" })
		layer({ "n", "x" }, "<right>", mc.nextCursor, { desc = "下一个光标" })
		layer({ "n", "x" }, "<leader>mx", mc.deleteCursor, { desc = "删除主光标" })
		layer("n", "<esc>", function()
			if mc.cursorsEnabled() then
				mc.clearCursors()
			else
				mc.enableCursors()
			end
		end, { desc = "清除多光标" })
	end)
	local actions = {
		n = {
			function()
				mc.matchAddCursor(1)
			end,
			"在下一个匹配处添加光标",
		},
		N = {
			function()
				mc.matchAddCursor(-1)
			end,
			"在上一个匹配处添加光标",
		},
		s = {
			function()
				mc.matchSkipCursor(1)
			end,
			"跳过下一个匹配",
		},
		S = {
			function()
				mc.matchSkipCursor(-1)
			end,
			"跳过上一个匹配",
		},
		j = {
			function()
				mc.lineAddCursor(1)
			end,
			"在下一行添加光标",
		},
		k = {
			function()
				mc.lineAddCursor(-1)
			end,
			"在上一行添加光标",
		},
		a = { mc.matchAllAddCursors, "在所有匹配处添加光标" },
		t = { mc.toggleCursor, "启用或停用光标" },
		q = { mc.clearCursors, "清除多光标" },
		g = { mc.addCursorOperator, "通过动作添加光标" },
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
