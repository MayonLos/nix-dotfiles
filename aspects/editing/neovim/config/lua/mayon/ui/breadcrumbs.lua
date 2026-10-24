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
	-- lz.n does not replay autocmds without an augroup. Navic's auto-attach
	-- handler has none, so explicitly attach the client that caused lazy loading.
	local navic = require("nvim-navic")
	for _, client in ipairs(vim.lsp.get_clients()) do
		if client:supports_method("textDocument/documentSymbol") then
			for buf in pairs(client.attached_buffers) do
				navic.attach(client, buf)
			end
		end
	end
end

return M
