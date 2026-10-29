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
		cmd = { "DapContinue", "DapToggleBreakpoint", "DapViewToggle", "DebugLuaListen" },
		keys = {
			{ "<leader>dc", debug_action("continue"), desc = "Continue debugging" },
			{ "<F5>", debug_action("continue"), desc = "Continue debugging" },
			{ "<leader>db", debug_action("toggle_breakpoint"), desc = "Toggle breakpoint" },
			{ "<F9>", debug_action("toggle_breakpoint"), desc = "Toggle breakpoint" },
			{ "<leader>dn", debug_action("step_over"), desc = "Step over" },
			{ "<F10>", debug_action("step_over"), desc = "Step over" },
			{ "<leader>di", debug_action("step_into"), desc = "Step into" },
			{ "<F11>", debug_action("step_into"), desc = "Step into" },
			{ "<leader>do", debug_action("step_out"), desc = "Step out" },
			{ "<S-F11>", debug_action("step_out"), desc = "Step out" },
			{ "<leader>dq", debug_action("disconnect"), desc = "Disconnect debugger" },
			{ "<leader>dt", debug_action("terminate"), desc = "Terminate debugging" },
			{ "<S-F5>", debug_action("terminate"), desc = "Terminate debugging" },
			{ "<leader>dC", debug_action("run_to_cursor"), desc = "Run to cursor" },
			{ "<leader>dR", debug_action("restart"), desc = "Restart debugging" },
			{ "<leader>dl", debug_action("run_last"), desc = "Run last configuration" },
			{ "<leader>dX", debug_action("clear_breakpoints"), desc = "Clear breakpoints" },
			{ "<leader>dp", debug_action("pause"), desc = "Pause debugging" },
			{
				"<leader>dB",
				function()
					require("mayon.features.debug").breakpoint("condition")
				end,
				desc = "Set conditional breakpoint",
			},
			{
				"<leader>dL",
				function()
					require("mayon.features.debug").breakpoint("log")
				end,
				desc = "Set logpoint",
			},
			{
				"<leader>ds",
				function()
					require("mayon.features.debug").select()
				end,
				desc = "Select configuration",
			},
			{
				"<leader>du",
				function()
					require("dap-view").toggle()
				end,
				desc = "Toggle debug panel",
			},
			{
				"<leader>dr",
				function()
					require("dap-view").open()
					require("dap-view").jump_to_view("repl")
				end,
				desc = "Open debug REPL",
			},
			{
				"<leader>dh",
				function()
					require("dap.ui.widgets").hover(nil, { border = "single" })
				end,
				desc = "Inspect value",
			},
			{
				"<leader>de",
				function()
					require("dap-view").add_expr()
				end,
				desc = "Add watch expression",
			},
			{
				"<leader>dj",
				function()
					require("mayon.features.java_debug").test_nearest_method()
				end,
				desc = "Debug nearest Java test",
			},
			{
				"<leader>dJ",
				function()
					require("mayon.features.java_debug").test_class()
				end,
				desc = "Debug Java test class",
			},
		},
		after = function()
			require("mayon.features.debug").setup()
		end,
	},
	{
		"grug-far.nvim",
		cmd = "GrugFar",
		after = function()
			require("grug-far").setup({ headerMaxWidth = 80, border = "single" })
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
			{ "<leader>xt", todo_picker, desc = "Find TODO comments" },
			{
				"]t",
				function()
					require("todo-comments").jump_next()
				end,
				desc = "Jump to next TODO",
			},
			{
				"[t",
				function()
					require("todo-comments").jump_prev()
				end,
				desc = "Jump to previous TODO",
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
