-- The original Nixvim Navic configuration, with plugin-owned LSP/cache handling.
local M = {}
local ready = false

function M.setup()
	if ready then
		return
	end
	ready = true
	require("nvim-navic").setup({
		lsp = { auto_attach = true },
		highlight = true,
		depth_limit = 3,
		depth_limit_indicator = "…",
		separator = " › ",
		safe_output = true,
	})
end

return M
