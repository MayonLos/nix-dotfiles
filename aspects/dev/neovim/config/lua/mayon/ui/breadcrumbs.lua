local M = {}
function M.setup()
	require("dropbar").setup({
		icons = {
			ui = { bar = { separator = " › " } },
			kinds = {
				file_icon = function(path)
					return require("mayon.ui.icons").get(path)
				end,
			},
		},
		bar = {
			enable = function(buf, win)
				return vim.api.nvim_win_is_valid(win)
					and vim.api.nvim_win_get_config(win).relative == ""
					and vim.bo[buf].buftype == ""
					and vim.bo[buf].filetype ~= "snacks_dashboard"
					and vim.bo[buf].filetype ~= "bigfile"
			end,
			padding = { left = 1, right = 1 },
		},
		menu = { win_configs = { border = "rounded" } },
	})
end
return M
