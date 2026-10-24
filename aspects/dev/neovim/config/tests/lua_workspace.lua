-- Exercise lazydev against the real LuaLS client using isolated project
-- fixtures. The wrapper is expected to start the production Nvim config.
assert(vim.g.mayon_config_loaded, "Lua workspace integration requires the production config")
assert(vim.fn.executable("lua-language-server") == 1, "lua-language-server is required for this check")
assert(vim.lsp.is_enabled("lua_ls"), "LuaLS must be enabled by the production configuration")

local lazydev_config = require("lazydev.config")
local lazydev_buffer = require("lazydev.buf")
local workspace_api = require("lazydev.workspace")
local project_root = vim.fn.tempname()
assert(vim.fn.mkdir(project_root, "p") == 1, "could not create isolated LuaLS fixture root")

local buffers, clients = {}, {}
local previous_lazydev_enabled = vim.g.lazydev_enabled
local initial_clients = {}
for _, client in ipairs(vim.lsp.get_clients({ name = "lua_ls" })) do
	initial_clients[client.id] = true
end

local function mkdir(path)
	assert(vim.fn.mkdir(path, "p") == 1, "could not create fixture directory: " .. path)
end

local function write(path, lines)
	assert(vim.fn.writefile(lines, path) == 0, "could not write isolated fixture: " .. path)
end

local function read(path)
	return table.concat(vim.fn.readfile(path, "b"), "\n")
end

local function open_lua(path, lines)
	write(path, lines)
	vim.cmd.edit(vim.fn.fnameescape(path))
	local buf = vim.api.nvim_get_current_buf()
	assert(vim.bo[buf].filetype == "lua", "fixture must have Lua filetype")
	buffers[#buffers + 1] = buf
	local attached = vim.wait(20000, function()
		return #vim.lsp.get_clients({ bufnr = buf, name = "lua_ls" }) > 0
	end, 50)
	assert(attached, "LuaLS did not attach to " .. path)
	local client = vim.lsp.get_clients({ bufnr = buf, name = "lua_ls" })[1]
	clients[client.id] = client
	return buf, client
end

local function project_file(name)
	local root = project_root .. "/" .. name
	mkdir(root .. "/nested")
	return root, root .. "/nested/main.lua"
end

local function has_path(paths, path)
	local expected = vim.uv.fs_realpath(path) or path
	for _, entry in ipairs(paths or {}) do
		local actual = vim.uv.fs_realpath(entry) or entry
		if vim.fs.normalize(actual) == vim.fs.normalize(expected) then
			return true
		end
	end
	return false
end

local function module_lua_root(name)
	local module = assert(vim.loader.find(name)[1], "module must be available in the wrapped plugin pack: " .. name)
	local marker = assert(module.modpath:find("/lua/", 1, true), "module path must have a Lua root: " .. module.modpath)
	return module.modpath:sub(1, marker - 1) .. "/lua"
end

local ok, err = xpcall(function()
	-- A regular project is rooted by the normal server markers. Requiring one
	-- plugin module should add only that plugin's Lua tree to the workspace.
	local ordinary_root, ordinary_file = project_file("ordinary")
	mkdir(ordinary_root .. "/.git")
	local ordinary_buf, ordinary_client = open_lua(ordinary_file, {
		"local module = require('blink.cmp')",
		"return module",
	})
	assert(
		vim.fs.normalize(ordinary_client.root_dir) == vim.fs.normalize(ordinary_root),
		"LuaLS root detection changed"
	)
	local ordinary_workspace =
		assert(workspace_api.find({ buf = ordinary_buf }), "lazydev must track the ordinary workspace")
	assert(ordinary_workspace:enabled(), "ordinary workspace should enable lazydev")
	assert(
		vim.wait(5000, function()
			return has_path(ordinary_workspace.library, module_lua_root("blink.cmp"))
		end, 25),
		"a required plugin module should add its Lua library on demand; found: "
			.. vim.inspect(ordinary_workspace.library)
	)
	local unrelated_lua_root = module_lua_root("conform")
	assert(
		not has_path(ordinary_workspace.library, unrelated_lua_root),
		"unrequired plugins must not be added to the workspace"
	)
	ordinary_workspace:update()
	local ordinary_settings = ordinary_workspace.settings
	local ordinary_library = vim.tbl_get(ordinary_settings, "Lua", "workspace", "library") or {}
	local runtime_path = vim.tbl_get(ordinary_settings, "Lua", "runtime", "path") or {}
	assert(
		vim.tbl_contains(runtime_path, "?.lua"),
		"LuaLS should retain lazydev's runtime module path; found: " .. vim.inspect(ordinary_settings)
	)
	assert(vim.tbl_contains(runtime_path, "?/init.lua"), "LuaLS should retain lazydev's runtime init path")
	assert(has_path(ordinary_library, module_lua_root("blink.cmp")), "the required plugin library should reach LuaLS")
	assert(not has_path(ordinary_library, unrelated_lua_root), "LuaLS must not receive every plugin library")
	assert(
		vim.tbl_get(ordinary_settings, "Lua", "workspace", "checkThirdParty") == false,
		"LuaLS third-party prompts must stay disabled"
	)
	assert(#ordinary_library < 32, "workspace library should stay small instead of copying the full runtimepath")

	-- Project-owned .luarc files must remain the owner's configuration. Check
	-- both JSON formats and a nested Lua file below each config.
	for _, extension in ipairs({ "json", "jsonc" }) do
		local root, path = project_file("configured-" .. extension)
		local config_path = root .. "/.luarc." .. extension
		local config_lines
		if extension == "json" then
			config_lines = {
				'{ "workspace.library": ["/project/owned/path"], "workspace.checkThirdParty": true }',
			}
		else
			config_lines = {
				"{",
				"  // project-owned LuaLS settings",
				'  "workspace.library": ["/project/owned/jsonc-path"],',
				'  "workspace.checkThirdParty": true',
				"}",
			}
		end
		write(config_path, config_lines)
		local before = read(config_path)
		local buf, client = open_lua(path, { "return require('blink.cmp')" })
		assert(vim.fs.normalize(client.root_dir) == vim.fs.normalize(root), "LuaLS must honor the project config root")
		assert(lazydev_config.is_enabled(root) == false, "lazydev must defer to an ancestor .luarc." .. extension)
		assert(not lazydev_buffer.attached[buf], "lazydev must not attach inside a project-owned LuaLS config")
		local disabled_workspace = assert(workspace_api.find({ buf = buf }))
		assert(not disabled_workspace:enabled(), "project-owned LuaLS config must disable lazydev workspace updates")
		assert(#disabled_workspace.library == 0, "disabled workspace must not receive lazydev plugin libraries")
		assert(vim.tbl_get(disabled_workspace.settings, "Lua", "workspace", "library") == nil)
		assert(read(config_path) == before, "lazydev must leave the project config bytes untouched")
	end

	-- The explicit global opt-out is also evaluated per workspace and does not
	-- attach lazydev or add libraries to the user's project.
	local disabled_root, disabled_file = project_file("global-disabled")
	mkdir(disabled_root .. "/.git")
	vim.g.lazydev_enabled = false
	local disabled_buf, disabled_client = open_lua(disabled_file, { "return require('blink.cmp')" })
	assert(
		vim.fs.normalize(disabled_client.root_dir) == vim.fs.normalize(disabled_root),
		"global opt-out must retain normal LuaLS rooting"
	)
	assert(lazydev_config.is_enabled(disabled_root) == false, "vim.g.lazydev_enabled=false must disable lazydev")
	assert(not lazydev_buffer.attached[disabled_buf], "global opt-out must prevent lazydev buffer attachment")
	local globally_disabled_workspace = assert(workspace_api.find({ buf = disabled_buf }))
	assert(not globally_disabled_workspace:enabled(), "global opt-out must disable workspace updates")
	assert(#globally_disabled_workspace.library == 0, "global opt-out must not add plugin libraries")
	assert(vim.tbl_get(globally_disabled_workspace.settings, "Lua", "workspace", "library") == nil)
end, debug.traceback)

-- Stop only clients and buffers created by this test and remove only its
-- unique temporary fixture tree, even when an assertion fails.
vim.g.lazydev_enabled = previous_lazydev_enabled
for id, client in pairs(clients) do
	if not initial_clients[id] and vim.lsp.get_client_by_id(id) then
		client:stop(true)
	end
end
for _, buf in ipairs(buffers) do
	if vim.api.nvim_buf_is_valid(buf) then
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end
end
assert(vim.fn.delete(project_root, "rf") == 0, "could not clean the isolated LuaLS fixture root")
if not ok then
	error(err)
end
print("LuaLS lazydev workspace integration passed")
