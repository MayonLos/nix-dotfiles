local M = {}

local function setup()
	require("lint").linters_by_ft = vim.deepcopy(require("mayon.generated").languages.linters)
	local group = vim.api.nvim_create_augroup("MayonLint", { clear = true })
	vim.api.nvim_create_autocmd({ "FileType", "BufWritePost", "InsertLeave" }, {
		group = group,
		callback = function()
			require("lint").try_lint()
		end,
	})
end

return { { "nvim-lint", event = { "BufReadPre", "BufNewFile" }, after = setup } }
