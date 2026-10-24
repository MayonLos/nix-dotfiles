local M = {}

local ready = false
function M.ensure()
	if ready then
		return
	end
	ready = true
	require("mayon.config.loader").pack("nvim-web-devicons")
	local matlab = {
		icon = "󰘨",
		color = require("mayon.generated").palette.orange,
		cterm_color = "173",
		name = "Matlab",
	}
	require("nvim-web-devicons").setup({
		override = {
			m = matlab,
			mlx = vim.tbl_extend("force", matlab, { name = "MatlabLiveScript" }),
			mat = vim.tbl_extend("force", matlab, { name = "MatlabData" }),
			slx = vim.tbl_extend("force", matlab, { name = "Simulink" }),
		},
	})
	vim.diagnostic.config({
		signs = {
			text = {
				[vim.diagnostic.severity.ERROR] = "󰅚 ",
				[vim.diagnostic.severity.WARN] = "󰀪 ",
				[vim.diagnostic.severity.INFO] = "󰋽 ",
				[vim.diagnostic.severity.HINT] = "󰌶 ",
			},
		},
	})
end

M.setup = M.ensure
return M
