local M = {}

local function is_neovim_config_buffer()
	local filename = vim.api.nvim_buf_get_name(0)
	return require("mayon.features.lua_workspace").is_config_path(filename)
end

local function setup()
	local lint = require("lint")
	lint.linters_by_ft = vim.deepcopy(require("mayon.generated").languages.linters)
	local luacheck = lint.linters.luacheck
	lint.linters.luacheck = function()
		local config = vim.deepcopy(luacheck)
		if is_neovim_config_buffer() then
			-- Only the managed Neovim config owns these runtime globals. Keep
			-- luacheck's unknown-global checks active in ordinary Lua projects.
			local stdin_index = vim.fn.index(config.args, "-")
			local args = { "--globals", "vim", "Snacks" }
			if stdin_index < 0 then
				vim.list_extend(config.args, args)
			else
				for index, argument in ipairs(args) do
					table.insert(config.args, stdin_index + index - 1, argument)
				end
			end
		end
		return config
	end
	local group = vim.api.nvim_create_augroup("MayonLint", { clear = true })
	vim.api.nvim_create_autocmd({ "FileType", "BufWritePost", "InsertLeave" }, {
		group = group,
		callback = function()
			require("lint").try_lint()
		end,
	})
end

return { { "nvim-lint", event = { "BufReadPre", "BufNewFile" }, after = setup } }
