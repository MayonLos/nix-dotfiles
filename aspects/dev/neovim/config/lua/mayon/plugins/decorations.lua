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
			-- One restrained inline message at the cursor; diagnostics elsewhere
			-- remain visible through native underlines and the sign column.
			require("tiny-inline-diagnostic").setup({
				preset = "minimal",
				transparent_bg = true,
				blend = { factor = 0 },
				signs = {
					left = "",
					right = "",
					diag = "▲",
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
					background = "MayonDiagnosticInline",
					mixing_color = "Normal",
				},
				options = {
					show_code = false,
					show_related = { enabled = false },
					show_source = { enabled = false },
					show_all_diags_on_cursorline = false,
					overflow = { mode = "oneline" },
					set_arrow_to_diag_color = false,
				},
			})
			-- The pinned plugin falls back to every diagnostic on a line when
			-- none intersects the cursor. Keep the inline view to one message;
			-- native signs/underlines and the diagnostics picker retain them all.
			local filter = require("tiny-inline-diagnostic.filter")
			local at_position = filter.at_position
			filter.at_position = function(opts, diagnostics, line, col)
				local candidates = at_position(opts, diagnostics, line, col)
				table.sort(candidates, function(a, b)
					if a.severity ~= b.severity then
						return a.severity < b.severity
					end
					return math.abs(a.col - col) < math.abs(b.col - col)
				end)
				return candidates[1] and { candidates[1] } or {}
			end
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
