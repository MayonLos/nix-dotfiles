local function todo_picker()
	-- Snacks 2.31 has no dedicated todo-comments source; keep the query editable.
	require("snacks").picker.grep({
		search = "\\b(TODO|FIX|FIXME|BUG|HACK|WARN|WARNING|XXX|PERF|OPTIM|NOTE|INFO|TEST|TESTING):",
		regex = true,
	})
end

local function debug_action(method)
	return function()
		require("dap")[method]()
	end
end

return {
	{
		"nvim-dap",
		keys = {
			{ "<leader>dc", debug_action("continue"), desc = "Debug · continue / attach" },
			{ "<leader>db", debug_action("toggle_breakpoint"), desc = "Debug · breakpoint" },
			{ "<leader>dn", debug_action("step_over"), desc = "Debug · step over" },
			{ "<leader>di", debug_action("step_into"), desc = "Debug · step into" },
			{ "<leader>do", debug_action("step_out"), desc = "Debug · step out" },
			{ "<leader>dq", debug_action("disconnect"), desc = "Debug · disconnect" },
			{
				"<leader>dr",
				function()
					require("dap").repl.toggle()
				end,
				desc = "Debug · REPL",
			},
			{
				"<leader>dh",
				function()
					require("dap.ui.widgets").hover()
				end,
				desc = "Debug · value",
			},
		},
		after = function()
			require("mayon.features.embedded").setup_dap()
		end,
	},
	{
		"grug-far.nvim",
		cmd = "GrugFar",
		after = function()
			require("grug-far").setup({ headerMaxWidth = 80, border = "rounded" })
		end,
	},
	{
		"which-key.nvim",
		event = "User MayonVeryLazy",
		after = function()
			require("mayon.ui.whichkey").setup()
			require("mayon.features.diagnostic_panel").setupQuickfix()
		end,
	},
	{
		"todo-comments.nvim",
		event = { "BufReadPost", "BufNewFile" },
		keys = {
			{ "<leader>xt", todo_picker, desc = "查找 TODO 注释" },
			{
				"]t",
				function()
					require("todo-comments").jump_next()
				end,
				desc = "下一个 TODO",
			},
			{
				"[t",
				function()
					require("todo-comments").jump_prev()
				end,
				desc = "上一个 TODO",
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
