-- Snacks owns file, buffer, project, symbol, diagnostic and help pickers.
local function pick(source, opts)
	return function()
		require("snacks").picker[source](opts)
	end
end

for _, spec in ipairs({
	{ "<leader>fr", "recent", "Find Recent Files" },
	{ "<leader>fp", "projects", "Find Projects" },
}) do
	vim.keymap.set("n", spec[1], pick(spec[2]), { desc = spec[3] })
end

return {
	{
		"oil.nvim",
		cmd = "Oil",
		keys = { { "-", desc = "Browse Parent Directory" } },
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
				desc = "Open Yazi File Manager",
			},
		},
		after = function()
			require("yazi").setup({ open_for_directories = false })
		end,
	},
}
