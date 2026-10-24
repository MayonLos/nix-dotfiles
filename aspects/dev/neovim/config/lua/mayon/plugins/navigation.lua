-- Snacks owns file, buffer, project, symbol, diagnostic and help pickers.
local function pick(source, opts)
	return function()
		require("snacks").picker[source](opts)
	end
end

for _, spec in ipairs({
	{ "<leader>fr", "recent", "最近打开的文件" },
	{ "<leader>fp", "projects", "查找项目" },
}) do
	vim.keymap.set("n", spec[1], pick(spec[2]), { desc = spec[3] })
end

return {
	{
		"oil.nvim",
		cmd = "Oil",
		keys = { { "-", desc = "编辑父目录" } },
		after = function()
			require("mayon.features.oil").setup()
		end,
	},
	{
		"yazi.nvim",
		keys = {
			{
				"<leader>fy",
				function()
					require("yazi").yazi()
				end,
				desc = "打开 Yazi 文件管理器",
			},
		},
		after = function()
			require("yazi").setup({ open_for_directories = false })
		end,
	},
}
