local M = {}

local function snacks_lua_root()
	local module = vim.loader.find("snacks")[1]
	if not module then
		return nil
	end
	local marker = module.modpath:find("/lua/", 1, true)
	return marker and (module.modpath:sub(1, marker - 1) .. "/lua") or nil
end

local function setup()
	require("lazydev").setup({
		library = {},
		-- Keep native LuaLS root detection, including projects with their own
		-- configuration. Lazydev remains responsible for LuaLS library injection.
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
	local group = vim.api.nvim_create_augroup("MayonLuaConfigLibrary", { clear = true })
	vim.api.nvim_create_autocmd("LspAttach", {
		group = group,
		callback = function(event)
			local client = vim.lsp.get_client_by_id(event.data and event.data.client_id)
			local filename = vim.api.nvim_buf_get_name(event.buf)
			local workspace_root = require("mayon.features.lua_workspace").root_for_path(filename)
			if not client or client.name ~= "lua_ls" or not workspace_root then
				return
			end
			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(event.buf) then
					return
				end
				local workspace = require("lazydev.workspace").find({ buf = event.buf })
				if workspace and workspace.root == workspace_root then
					-- The Snacks API belongs only to Neovim's own configuration
					-- workspace, never to ordinary Lua projects.
					local library = snacks_lua_root()
					if library then
						workspace:add(library)
					end
				end
			end)
		end,
	})
end

return { { "lazydev.nvim", ft = "lua", after = setup } }
