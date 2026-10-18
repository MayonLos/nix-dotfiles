local M = {}

function M.setup()
	require("grug-far").setup({ headerMaxWidth = 80, border = "rounded" })
	require("which-key").setup({
		spec = {
			{ "<leader>m", group = "󰇀 Multiple cursors", mode = { "n", "x" } },
			{ "<leader>f", group = "󰍉 Find" },
			{ "<leader>s", group = "󰛔 Search" },
			{ "<leader>g", group = "󰊢 Git" },
			{ "<leader>l", group = "󰒋 LSP" },
			{ "<leader>w", group = " Window", proxy = "<C-w>" },
			{ "<leader>u", group = "󰒓 Utility / Toggle" },
			{ "<leader>a", group = "󰚩 AI" },
			{ "<leader>ac", group = "󰆍 CLI agent" },
			{ "<leader>b", group = "󰓩 Buffer" },
			{ "<leader>c", group = " Code" },
			{ "<leader>n", group = "󰈙 Docs" },
			{ "<leader>x", group = "󰔫 Diagnostics" },
			{ "<leader>p", group = "󰆓 Session" },
		},
		win = { border = "rounded", padding = { 0, 1 }, wo = { winblend = 0 } },
	})
	vim.keymap.set({ "n", "v" }, "<leader>sr", "<cmd>GrugFar<cr>", { desc = "Search and replace" })
end

return M
