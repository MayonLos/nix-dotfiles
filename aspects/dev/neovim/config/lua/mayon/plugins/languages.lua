return {
	{
		"nvim-lspconfig",
		event = "FileType",
		after = function()
			local function ordinary(buf)
				return vim.bo[buf].buftype == "" and vim.bo[buf].filetype ~= "" and vim.bo[buf].filetype ~= "bigfile"
			end
			local function start(buf)
				require("mayon.lsp").setup()
				local folds = require("mayon.features.folds")
				folds.setup()
				folds.apply(buf)
			end
			local buf = vim.api.nvim_get_current_buf()
			if ordinary(buf) then
				start(buf)
				return
			end
			-- Dashboard, prompt and terminal FileTypes do not need the LSP graph.
			local id
			id = vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("MayonFirstFileLsp", { clear = true }),
				callback = function(ev)
					if ordinary(ev.buf) then
						vim.api.nvim_del_autocmd(id)
						start(ev.buf)
					end
				end,
			})
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
			require("mayon.features.diagnostic_panel").setupTrouble()
		end,
	},
}
