local M = {}
local provider_module = "codecompanion.providers.completion.blink"
local provider_methods = {
	enabled = true,
	get_trigger_characters = true,
	get_completions = true,
	execute = true,
}

local function get_provider_module()
	if not package.loaded[provider_module] then
		require("lz.n").trigger_load("codecompanion.nvim")
	end
	return require(provider_module)
end

function M.new(opts, config)
	local delegate
	local function get_delegate()
		if not delegate then
			delegate = get_provider_module().new(opts, config)
		end
		return delegate
	end

	return setmetatable({}, {
		__index = function(_, method)
			if not provider_methods[method] then
				return nil
			end

			if method == "enabled" then
				return function()
					if package.loaded[provider_module] then
						return get_delegate():enabled()
					end

					local filetype = vim.bo.filetype
					return filetype == "codecompanion" or filetype == "codecompanion_input"
				end
			end

			return function(_, ...)
				local provider = get_delegate()
				local callback = provider[method]
				if callback then
					return callback(provider, ...)
				end
			end
		end,
	})
end

return M
