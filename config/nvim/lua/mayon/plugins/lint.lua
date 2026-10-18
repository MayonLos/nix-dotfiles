local M = {}

function M.setup()
	require("lint").linters_by_ft = {
		python = { "ruff" },
		lua = { "luacheck" },
		sh = { "shellcheck" },
		bash = { "shellcheck" },
	}
	local group = vim.api.nvim_create_augroup("MayonLint", { clear = true })
	vim.api.nvim_create_autocmd({ "FileType", "BufWritePost", "InsertLeave" }, {
		group = group,
		callback = function()
			require("lint").try_lint()
		end,
	})
end

return M
