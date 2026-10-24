local function todo_picker()
	-- Snacks 2.31 has no dedicated todo-comments source. Use its grep picker
	-- with the same keyword shape and leave the query editable in the picker.
	require("snacks").picker.grep({
		search = "\\b(TODO|FIX|FIXME|BUG|HACK|WARN|WARNING|XXX|PERF|OPTIM|NOTE|INFO|TEST|TESTING):",
		regex = true,
	})
end

return {
	{
		"grug-far.nvim",
		cmd = "GrugFar",
		keys = {
			{
				"<leader>sr",
				"<cmd>GrugFar<cr>",
				desc = "Search and replace",
			},
		},
		after = function()
			require("grug-far").setup({ headerMaxWidth = 80, border = "rounded" })
		end,
	},
	{
		"which-key.nvim",
		event = "User MayonVeryLazy",
		after = function()
			require("which-key").setup({
				spec = {
					{ "<leader>f", group = "Files" },
					{ "<leader>s", group = "Search" },
					{ "<leader>g", group = "Git" },
					{ "<leader>c", group = "Code" },
					{ "<leader>d", group = "Debug" },
					{ "<leader>r", group = "Run" },
					{ "<leader>a", group = "AI" },
					{ "<leader>u", group = "UI" },
					{ "<leader>x", group = "Diagnostics" },
					{ "<leader>w", group = "Windows", proxy = "<C-w>" },
					{ "<leader>b", group = "Buffers" },
					-- Keep established secondary groups discoverable.
					{ "<leader>ac", group = "CLI agents" },
					{ "<leader>l", group = "LSP" },
					{ "<leader>m", group = "Multiple cursors", mode = { "n", "x" } },
					{ "<leader>n", group = "Docs" },
					{ "<leader>p", group = "Sessions" },
				},
				win = { border = "rounded", padding = { 0, 1 }, wo = { winblend = 0 } },
			})
		end,
	},
	{
		"todo-comments.nvim",
		event = { "BufReadPost", "BufNewFile" },
		keys = {
			{ "<leader>st", todo_picker, desc = "Search TODO comments" },
			{ "<leader>xt", todo_picker, desc = "Search TODO comments" },
			{
				"]t",
				function()
					require("todo-comments").jump_next()
				end,
				desc = "Next TODO comment",
			},
			{
				"[t",
				function()
					require("todo-comments").jump_prev()
				end,
				desc = "Previous TODO comment",
			},
		},
		after = function()
			local palette = require("mayon.generated").palette
			require("todo-comments").setup({
				colors = {
					error = { palette.red },
					warning = { palette.orange },
					info = { palette.blue },
					hint = { palette.cyan },
					test = { palette.green },
					default = { palette.purple },
				},
			})
		end,
	},
}
