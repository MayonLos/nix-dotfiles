-- One picker surface for files, code, Git, help and history.
local function pick(source)
	return function()
		require("snacks").picker[source]()
	end
end
local M = {}
function M.keys()
	for _, spec in ipairs({
		{ "<leader>ff", "files", "Find files" },
		{ "<leader>fg", "grep", "Live grep" },
		{ "<leader>fb", "buffers", "Buffers" },
		{ "<leader>fr", "recent", "Recent files" },
		{ "<leader>fh", "help", "Help" },
		{ "<leader>f.", "lines", "Buffer lines" },
		{ "<leader>fp", "projects", "Projects" },
		{ "<leader>fs", "lsp_symbols", "Document symbols" },
		{ "<leader>fS", "lsp_workspace_symbols", "Workspace symbols" },
		{ "<leader>fd", "diagnostics", "Diagnostics" },
		{ "<leader>fk", "keymaps", "Keymaps" },
		{ "<leader>f:", "command_history", "Command history" },
		{ "<leader>f/", "resume", "Resume picker" },
		{ "<leader>g/", "git_status", "Git status picker" },
		{ "<leader>gl", "git_log", "Git log picker" },
		{ "<leader>gL", "git_branches", "Git branches picker" },
	}) do
		vim.keymap.set("n", spec[1], pick(spec[2]), { desc = spec[3] })
	end
end
-- Key registration has no optional plugin cost; Snacks itself is a startup plugin.
M.keys()
return {
	{
		"oil.nvim",
		cmd = "Oil",
		keys = { { "-", desc = "Open parent directory in Oil" } },
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
				desc = "Yazi file manager",
			},
		},
		after = function()
			require("yazi").setup({ open_for_directories = false })
		end,
	},
}
