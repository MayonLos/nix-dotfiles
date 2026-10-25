-- Exercise lazydev against the real LuaLS client using isolated project
-- fixtures. The wrapper is expected to start the production Nvim config.
assert(vim.g.mayon_config_loaded, "Lua workspace integration requires the production config")
assert(vim.fn.executable("lua-language-server") == 1, "lua-language-server is required for this check")
assert(vim.lsp.is_enabled("lua_ls"), "LuaLS must be enabled by the production configuration")

local lazydev_config = require("lazydev.config")
local lazydev_buffer = require("lazydev.buf")
local workspace_api = require("lazydev.workspace")
local config_workspace_roots = require("mayon.features.lua_workspace")
local active_config_dir = assert(vim.env.NVIM_CONFIG_DIR, "the wrapped config directory is required")
local generated = require("mayon.generated")
local previous_config_dir = vim.env.NVIM_CONFIG_DIR
local previous_nix_options = generated.nix_options
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

local function open_existing_lua(path)
	vim.cmd.edit(vim.fn.fnameescape(path))
	local buf = vim.api.nvim_get_current_buf()
	assert(vim.bo[buf].filetype == "lua", "configuration source must have Lua filetype: " .. path)
	buffers[#buffers + 1] = buf
	local attached = vim.wait(20000, function()
		return #vim.lsp.get_clients({ bufnr = buf, name = "lua_ls" }) > 0
	end, 50)
	assert(attached, "LuaLS did not attach to configuration source " .. path)
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

local function has_undefined_global(buf, name)
	for _, diagnostic in ipairs(vim.diagnostic.get(buf)) do
		local message = tostring(diagnostic.message):lower()
		if message:find("undefined global", 1, true) and message:find(name:lower(), 1, true) then
			return true
		end
	end
	return false
end

local ok, err = xpcall(function()
	-- A regular project is rooted by the normal server markers. Requiring one
	-- plugin module should add only that plugin's Lua tree to the workspace.
	local ordinary_root, ordinary_file = project_file("ordinary")
	mkdir(ordinary_root .. "/.git")
	local ordinary_buf, ordinary_client = open_lua(ordinary_file, {
		"local module = require('conform')",
		"return Snacks.picker.files, vim.api.nvim_get_current_buf(), computer, module",
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
			return has_path(ordinary_workspace.library, module_lua_root("conform"))
		end, 25),
		"a required plugin module should add its Lua library on demand; found: "
			.. vim.inspect(ordinary_workspace.library)
	)
	local unrelated_lua_root = module_lua_root("snacks")
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
	assert(has_path(ordinary_library, module_lua_root("conform")), "the required plugin library should reach LuaLS")
	assert(not has_path(ordinary_library, module_lua_root("snacks")), "Snacks types must stay config-workspace local")
	assert(
		not vim.tbl_get(ordinary_settings, "Lua", "diagnostics", "globals"),
		"ordinary Lua workspaces must not inherit Neovim runtime globals"
	)
	assert(
		vim.wait(20000, function()
			return has_undefined_global(ordinary_buf, "Snacks") and has_undefined_global(ordinary_buf, "computer")
		end, 50),
		"ordinary Lua projects must still report undefined Snacks and OpenComputers globals; diagnostics: "
			.. vim.inspect(vim.diagnostic.get(ordinary_buf))
	)
	assert(not has_path(ordinary_library, unrelated_lua_root), "LuaLS must not receive every plugin library")
	assert(
		vim.tbl_get(ordinary_settings, "Lua", "workspace", "checkThirdParty") == false,
		"LuaLS third-party prompts must stay disabled"
	)
	assert(#ordinary_library < 32, "workspace library should stay small instead of copying the full runtimepath")

	-- Check the actual packaged configuration sources with LuaLS. This catches
	-- undefined globals in the editor config without weakening that diagnostic.
	local checkout_root = project_root .. "/live-source-checkout"
	local config_dir = checkout_root .. "/aspects/dev/neovim/config"
	mkdir(checkout_root .. "/aspects/dev/neovim")
	local copy_output = vim.fn.system({ "cp", "-R", active_config_dir, config_dir })
	assert(vim.v.shell_error == 0, "could not copy immutable config into isolated flake: " .. copy_output)
	local chmod_output = vim.fn.system({ "chmod", "-R", "u+w", config_dir })
	assert(vim.v.shell_error == 0, "could not make temporary config copy removable: " .. chmod_output)
	write(checkout_root .. "/flake.nix", { "{}" })
	local normalized_config_dir = vim.uv.fs_realpath(config_dir) or vim.fs.normalize(config_dir)
	local normalized_store_config_dir = vim.uv.fs_realpath(active_config_dir) or vim.fs.normalize(active_config_dir)
	generated.nix_options = { flake = checkout_root, host = "nixos-btw" }
	vim.env.NVIM_CONFIG_DIR = active_config_dir
	assert(
		config_workspace_roots.root_for_path(active_config_dir .. "/lua/mayon/lsp/servers.lua")
			== normalized_store_config_dir
	)
	assert(config_workspace_roots.root_for_path(config_dir .. "/lua/mayon/lsp/servers.lua") == normalized_config_dir)
	assert(
		config_workspace_roots.root_for_path(checkout_root .. "/aspects/dev/neovim/README.md") == nil,
		"the config roots must not expand to the full repository"
	)
	local store_buf, store_client = open_existing_lua(active_config_dir .. "/lua/mayon/lsp/servers.lua")
	assert(
		vim.fs.normalize(store_client.root_dir) == normalized_store_config_dir,
		"the package's immutable store config must have a scoped LuaLS workspace"
	)
	local generated_files = { ["generated.lua"] = true, ["generated_highlights.lua"] = true }
	local config_files = {}
	for _, path in ipairs(vim.fn.glob(config_dir .. "/lua/**/*.lua", false, true)) do
		if not generated_files[vim.fs.basename(path)] then
			config_files[#config_files + 1] = path
		end
	end
	assert(#config_files > 0, "no Lua configuration sources found under " .. config_dir)
	local config_clients, config_progress = {}, {}
	local progress_group = vim.api.nvim_create_augroup("MayonLuaWorkspaceProgressCheck", { clear = true })
	vim.api.nvim_create_autocmd("LspProgress", {
		group = progress_group,
		callback = function(event)
			local data = event.data and event.data.params
			local value = data and data.value
			if value and value.kind then
				config_progress[#config_progress + 1] = {
					client_id = event.data.client_id,
					kind = value.kind,
					title = value.title,
				}
			end
		end,
	})
	local config_buffers = {}
	for _, path in ipairs(config_files) do
		local buf, client = open_existing_lua(path)
		assert(
			vim.fs.normalize(client.root_dir) == normalized_config_dir,
			"Neovim configuration LuaLS must have its own scoped workspace"
		)
		config_clients[client.id] = client
		config_buffers[#config_buffers + 1] = { buf = buf, client = client, path = path }
	end
	local config_analysis_finished = vim.wait(30000, function()
		local saw_end = false
		for _, progress in ipairs(config_progress) do
			if config_clients[progress.client_id] and progress.kind == "end" then
				saw_end = true
				break
			end
		end
		if not saw_end then
			return false
		end
		for _, client in pairs(config_clients) do
			if next(client.progress.pending) ~= nil then
				return false
			end
		end
		return true
	end, 50)
	assert(
		config_analysis_finished,
		"LuaLS did not finish a work-done progress cycle for configuration sources within 30 seconds; progress: "
			.. vim.inspect(config_progress)
	)
	local config_workspace = assert(workspace_api.find({ buf = config_buffers[1].buf }))
	config_workspace:update()
	local config_settings = config_workspace.settings
	local config_globals = vim.tbl_get(config_settings, "Lua", "diagnostics", "globals") or {}
	assert(vim.tbl_contains(config_globals, "vim") and vim.tbl_contains(config_globals, "Snacks"))
	assert(
		has_path(vim.tbl_get(config_settings, "Lua", "workspace", "library") or {}, module_lua_root("snacks")),
		"Neovim configuration LuaLS must receive Snacks types"
	)
	local store_workspace = assert(workspace_api.find({ buf = store_buf }))
	store_workspace:update()
	assert(store_workspace.root == normalized_store_config_dir, "the packaged config workspace root should stay exact")
	local store_globals = vim.tbl_get(store_workspace.settings, "Lua", "diagnostics", "globals") or {}
	assert(vim.tbl_contains(store_globals, "vim") and vim.tbl_contains(store_globals, "Snacks"))
	assert(
		has_path(vim.tbl_get(store_workspace.settings, "Lua", "workspace", "library") or {}, module_lua_root("snacks")),
		"the packaged config workspace should receive Snacks API types; workspace="
			.. vim.inspect({
				root = store_workspace.root,
				library = store_workspace.library,
				settings = store_workspace.settings,
			})
	)
	for _, item in ipairs(config_buffers) do
		for _, diagnostic in ipairs(vim.diagnostic.get(item.buf)) do
			local code = type(diagnostic.code) == "string" and diagnostic.code:lower() or ""
			local message = tostring(diagnostic.message):lower()
			assert(
				code ~= "undefined-global" and not message:find("undefined global", 1, true),
				("LuaLS reported an undefined global in %s: %s"):format(item.path, diagnostic.message)
			)
		end
	end

	-- Luacheck remains available for explicit checks but is not run alongside
	-- LuaLS on project buffers, since only LuaLS reads project-owned .luarc data.
	-- Exercise its scoped manual config on a package source and ordinary source.
	require("lz.n").trigger_load("nvim-lint")
	local lint = require("lint")
	assert(not lint.linters_by_ft.lua, "Lua buffers should use LuaLS diagnostics without duplicate luacheck output")
	assert(vim.fn.executable("luacheck") == 1, "luacheck is required for this check")
	local function has_luacheck_code(buf, wanted)
		vim.api.nvim_set_current_buf(buf)
		local linter = lint.linters.luacheck()
		local args = { linter.cmd }
		vim.list_extend(args, linter.args)
		local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
		local output = vim.fn.system(args, table.concat(lines, "\n"))
		return output:find("(W" .. wanted .. ")", 1, true) ~= nil, output
	end
	local math_preview = assert(
		vim.tbl_filter(function(item)
			return item.path:match("/features/math_preview%.lua$") ~= nil
		end, config_buffers)[1],
		"math_preview.lua must be part of the packaged source scan"
	)
	local math_preview_has_w113, math_preview_output = has_luacheck_code(math_preview.buf, 113)
	assert(not math_preview_has_w113, "Neovim config math_preview.lua must not have W113:\n" .. math_preview_output)

	local source_root = project_root .. "/checkout-fixture"
	local source_config = source_root .. "/aspects/dev/neovim/config"
	mkdir(source_config .. "/lua")
	write(source_root .. "/flake.nix", { "{}" })
	mkdir(source_root .. "/aspects/dev/neovim")
	write(source_root .. "/aspects/dev/neovim/README.md", { "# Neovim fixture" })
	generated.nix_options = { flake = source_root }
	local source_buf = open_lua(source_config .. "/lua/runtime.lua", {
		"return vim.api.nvim_get_current_buf(), Snacks.picker.files",
	})
	local source_linter = lint.linters.luacheck()
	assert(vim.tbl_contains(source_linter.args, "--globals"), "checkout config should add scoped globals")
	assert(vim.tbl_contains(source_linter.args, "vim") and vim.tbl_contains(source_linter.args, "Snacks"))
	local source_has_w113, source_output = has_luacheck_code(source_buf, 113)
	assert(not source_has_w113, "checkout Neovim config should allow vim and Snacks:\n" .. source_output)

	local lint_root, lint_file = project_file("luacheck-ordinary")
	mkdir(lint_root .. "/.git")
	local ordinary_lint_buf = open_lua(lint_file, { "return MAYON_LUA_LINT_UNKNOWN_GLOBAL" })
	local ordinary_linter = lint.linters.luacheck()
	assert(not vim.tbl_contains(ordinary_linter.args, "--globals"), "ordinary Lua projects must not inherit globals")
	local ordinary_has_w113, ordinary_output = has_luacheck_code(ordinary_lint_buf, 113)
	assert(ordinary_has_w113, "ordinary Lua projects must still report W113:\n" .. ordinary_output)

	local probe_root, probe_file = project_file("undefined-probe")
	mkdir(probe_root .. "/.git")
	local probe_buf = open_lua(probe_file, { "return MAYON_LUALS_UNDEFINED_GLOBAL_PROBE" })
	local undefined_global_reported = vim.wait(20000, function()
		for _, diagnostic in ipairs(vim.diagnostic.get(probe_buf)) do
			local code = type(diagnostic.code) == "string" and diagnostic.code:lower() or ""
			local message = tostring(diagnostic.message):lower()
			if code == "undefined-global" or message:find("undefined global", 1, true) then
				return true
			end
		end
		return false
	end, 50)
	assert(undefined_global_reported, "LuaLS must report an intentionally undefined global")

	-- Project-owned .luarc files must remain the owner's configuration. Check
	-- both JSON formats and a nested Lua file below each config.
	for _, scenario in ipairs({ "json", "jsonc", "managed-ancestor" }) do
		local extension = scenario == "managed-ancestor" and "json" or scenario
		local root, path = project_file("configured-" .. scenario)
		local configured_env = vim.env.NVIM_CONFIG_DIR
		if scenario == "managed-ancestor" then
			vim.env.NVIM_CONFIG_DIR = root .. "/nested"
		end
		local library = root .. "/lua"
		mkdir(library)
		write(library .. "/project_api.lua", {
			"---@meta",
			"---@class projectApi",
			"---@field answer number",
			"---@type projectApi",
			"projectApi = {}",
		})
		local config_path = root .. "/.luarc." .. extension
		local config_lines
		if extension == "json" then
			config_lines = {
				'{ "runtime.version": "Lua 5.2", "diagnostics.globals": ["PROJECT_LUARC_GLOBAL", "computer"], '
					.. '"workspace.library": ['
					.. vim.json.encode(library)
					.. '], "workspace.checkThirdParty": true }',
			}
		else
			config_lines = {
				"{",
				"  // project-owned LuaLS settings",
				'  "runtime.version": "Lua 5.2",',
				'  "diagnostics.globals": ["PROJECT_LUARC_GLOBAL", "computer"],',
				'  "workspace.library": [' .. vim.json.encode(library) .. "],",
				'  "workspace.checkThirdParty": true',
				"}",
			}
		end
		write(config_path, config_lines)
		local before = read(config_path)
		local buf, client = open_lua(path, {
			"return PROJECT_LUARC_GLOBAL, projectApi.answer, vim.api, Snacks.picker",
		})
		assert(vim.fs.normalize(client.root_dir) == vim.fs.normalize(root), "LuaLS must honor the project config root")
		assert(lazydev_config.is_enabled(root) == false, "lazydev must defer to an ancestor .luarc." .. extension)
		assert(not lazydev_buffer.attached[buf], "lazydev must not attach inside a project-owned LuaLS config")
		assert(
			vim.tbl_get(client.config.settings, "Lua", "runtime", "version") == nil,
			"editor Lua runtime settings must not override the project's .luarc"
		)
		assert(
			vim.tbl_get(client.config.settings, "Lua", "diagnostics", "globals") == nil,
			"editor globals must not be sent to ordinary Lua projects"
		)
		assert(
			vim.tbl_get(client.config.settings, "Lua", "workspace", "library") == nil,
			"editor libraries must not replace project-owned libraries"
		)
		local disabled_workspace = assert(workspace_api.find({ buf = buf }))
		assert(not disabled_workspace:enabled(), "project-owned LuaLS config must disable lazydev workspace updates")
		assert(
			not has_path(disabled_workspace.library, module_lua_root("snacks")),
			"project-owned LuaLS config must not inherit the Neovim Snacks library"
		)
		assert(vim.tbl_get(disabled_workspace.settings, "Lua", "workspace", "library") == nil)
		local project_config_applied = vim.wait(20000, function()
			local diagnostics = vim.diagnostic.get(buf)
			local undefined = {}
			for _, diagnostic in ipairs(diagnostics) do
				local message = tostring(diagnostic.message):lower()
				if message:find("undefined global", 1, true) then
					for _, name in ipairs({ "vim", "snacks" }) do
						if message:find(name, 1, true) then
							undefined[name] = true
						end
					end
				end
			end
			return undefined["vim"] and undefined["snacks"]
		end, 50)
		assert(project_config_applied, "LuaLS did not analyze the .luarc project buffer")
		assert(
			not has_undefined_global(buf, "PROJECT_LUARC_GLOBAL"),
			"the project-owned .luarc global declaration was not honored"
		)
		assert(not has_undefined_global(buf, "computer"), "the project-owned OpenComputers global was not honored")
		assert(not has_undefined_global(buf, "projectApi"), "the project-owned .luarc library was not loaded")
		assert(
			has_undefined_global(buf, "vim") and has_undefined_global(buf, "Snacks"),
			"Neovim globals leaked into a project that owns its .luarc: " .. vim.inspect(vim.diagnostic.get(buf))
		)
		assert(read(config_path) == before, "lazydev must leave the project config bytes untouched")
		vim.env.NVIM_CONFIG_DIR = configured_env
	end

	-- The explicit global opt-out is also evaluated per workspace and does not
	-- attach lazydev or add libraries to the user's project.
	local disabled_root, disabled_file = project_file("global-disabled")
	mkdir(disabled_root .. "/.git")
	vim.g.lazydev_enabled = false
	local disabled_buf, disabled_client = open_lua(disabled_file, { "return require('snacks')" })
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
vim.env.NVIM_CONFIG_DIR = previous_config_dir
generated.nix_options = previous_nix_options
pcall(vim.api.nvim_del_augroup_by_name, "MayonLuaWorkspaceProgressCheck")
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
