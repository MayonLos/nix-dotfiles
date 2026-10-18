local M = {}

function M.setup()
	require("lazydev").setup({
		library = {},
		-- Keep native LuaLS root detection, including projects with their own
		-- configuration. Blink uses its explicit provider instead of nvim-cmp.
		integrations = { lspconfig = false, cmp = false },
		enabled = function(root)
			if vim.g.lazydev_enabled == false then
				return false
			end
			if not root or root == "single" or root == "global" then
				root = vim.fs.dirname(vim.api.nvim_buf_get_name(0)) or vim.uv.cwd()
			end
			return not vim.fs.find({ ".luarc.json", ".luarc.jsonc" }, { path = root, upward = true })[1]
		end,
	})
end

return M
