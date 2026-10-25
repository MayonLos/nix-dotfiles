return {
	{
		"nvim-web-devicons",
		-- Load on the first file; visible recent-file rows can also request icons.
		event = { "BufReadPre", "BufNewFile" },
		after = function()
			require("mayon.ui.icons").ensure()
		end,
	},
	{
		"rainbow-delimiters.nvim",
		event = { "BufReadPost", "BufNewFile" },
		after = function()
			require("rainbow-delimiters.setup").setup({
				condition = function(bufnr)
					return vim.bo[bufnr].filetype ~= "bigfile"
				end,
			})
			-- BufReadPost fires after the current buffer's FileType event, so the
			-- plugin's FileType autocmd cannot attach this first buffer by itself.
			if vim.bo.filetype ~= "bigfile" then
				require("rainbow-delimiters").enable(0)
			end
		end,
	},
	{
		"nvim-highlight-colors",
		event = { "BufReadPost", "BufNewFile" },
		after = function()
			require("nvim-highlight-colors").setup(require("mayon.ui.extras").color_options())
		end,
	},
	{
		"tiny-inline-diagnostic.nvim",
		event = "User MayonVeryLazy",
		after = function()
			-- Rounded end caps with low-contrast severity tint on the cursor line.
			require("tiny-inline-diagnostic").setup({
				preset = "modern",
				transparent_bg = false,
				transparent_cursorline = false,
				blend = { factor = 0.12 },
				signs = {
					left = "",
					right = "",
					diag = "•",
					arrow = "",
					up_arrow = "",
					vertical = "",
					vertical_end = "",
				},
				hi = {
					error = "DiagnosticError",
					warn = "DiagnosticWarn",
					info = "DiagnosticInfo",
					hint = "DiagnosticHint",
					arrow = "NonText",
					background = "CursorLine",
					mixing_color = "Normal",
				},
				options = {
					show_code = false,
					show_related = { enabled = false },
					show_source = { enabled = false },
					show_all_diags_on_cursorline = true,
					set_arrow_to_diag_color = false,
				},
			})
			-- The plugin rebuilds its groups on ColorScheme. Restore the palette
			-- body color after its listener, keeping severity on the gutter signs.
			vim.api.nvim_create_autocmd("ColorScheme", {
				group = vim.api.nvim_create_augroup("MayonDiagnosticTheme", { clear = true }),
				callback = function()
					require("mayon.ui.theme").refresh()
				end,
			})
		end,
	},
	{
		"tiny-glimmer.nvim",
		event = "User MayonVeryLazy",
		after = function()
			require("mayon.ui.motion").setup()
		end,
	},
}
