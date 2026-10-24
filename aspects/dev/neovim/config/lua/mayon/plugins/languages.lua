return {
	{
		"nvim-lspconfig",
		event = { "BufReadPre", "BufNewFile" },
		after = function()
			require("mayon.config.loader").pack("blink.cmp")
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
		"noice.nvim",
		event = "User MayonVeryLazy",
		cmd = { "Noice", "NoiceHistory", "NoiceErrors", "NoiceDismiss" },
		after = function()
			require("mayon.ui.noice").setup()
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
