return {
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
		"nvim-colorizer.lua",
		event = { "BufReadPost", "BufNewFile" },
		after = function()
			require("colorizer").setup({ filetypes = { "lua", "nix" } })
		end,
	},
	{
		"tiny-inline-diagnostic.nvim",
		event = "User MayonVeryLazy",
		after = function()
			require("tiny-inline-diagnostic").setup({})
		end,
	},
	{
		"satellite.nvim",
		event = { "BufReadPost", "BufNewFile" },
		after = function()
			require("satellite").setup({
				current_only = false,
				winblend = 0,
				width = 2,
				zindex = 40,
				handlers = {
					cursor = { enable = false },
					search = { enable = true },
					diagnostic = { enable = true, min_severity = vim.diagnostic.severity.HINT },
					gitsigns = {
						enable = true,
						signs = { add = "│", change = "│", delete = "-" },
					},
					marks = { enable = false },
				},
			})
		end,
	},
	{
		"incline.nvim",
		event = { "BufReadPost", "BufNewFile" },
		after = function()
			require("incline").setup({
				hide = { only_win = true },
				render = function(props)
					local name = vim.fn.fnamemodify(vim.api.nvim_buf_get_name(props.buf), ":t")
					if name == "" then
						return nil
					end
					return { { " " .. name .. " ", group = "InclineNormal" } }
				end,
			})
		end,
	},
}
