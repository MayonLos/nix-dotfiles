return {
	{
		"nvim-lspconfig",
		event = { "BufReadPre", "BufNewFile" },
		after = function()
			require("mayon.lsp").setup()
			require("mayon.features.folds").setup()
		end,
	},
	{
		"nvim-navic",
		event = "LspAttach",
		after = function()
			require("mayon.ui.breadcrumbs").setup()
		end,
	},
	{
		"trouble.nvim",
		cmd = "Trouble",
		after = function()
			require("trouble").setup({
				focus = true,
				icons = { indent = { last = "╰╴" } },
				preview = { type = "main", scratch = false },
			})
		end,
	},
}
