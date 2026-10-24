local function todo_picker()
	-- Snacks 2.31 has no dedicated todo-comments source; keep the query editable.
	require("snacks").picker.grep({
		search = "\\b(TODO|FIX|FIXME|BUG|HACK|WARN|WARNING|XXX|PERF|OPTIM|NOTE|INFO|TEST|TESTING):",
		regex = true,
	})
end

return {
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
			require("which-key").setup({
				spec = {
					{ "<leader>f", group = "文件", icon = "󰈔 " },
					{ "<leader>s", group = "搜索", icon = " " },
					{ "<leader>g", group = "Git", icon = "󰊢 " },
					{ "<leader>c", group = "代码", icon = "󰅩 " },
					{ "<leader>a", group = "AI", icon = "󰚩 " },
					{ "<leader>x", group = "列表", icon = "󰓙 " },
					{ "<leader>u", group = "界面", icon = "󰔎 " },
					{ "<leader>t", group = "终端", icon = " " },
					{ "<leader>p", group = "项目与会话", icon = "󰉋 " },
					{ "<leader>b", group = "缓冲区", icon = "󰓩 " },
					{ "<leader>l", group = "语言服务", icon = "󰿘 " },
					{ "<leader>m", group = "多光标", mode = { "n", "x" }, icon = "󰗧 " },
					{ "<leader>n", group = "文档", icon = "󰈙 " },
				},
				win = { border = "rounded", padding = { 0, 1 }, wo = { winblend = 0 } },
			})
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
