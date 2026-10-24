-- Run using the development wrapper and an isolated XDG tree; see run.py.
local uv = vim.uv
local started = vim.g.r10_started or uv.hrtime()
local function ms()
	return (uv.hrtime() - started) / 1e6
end
local server = assert(vim.env.BENCH_SERVER)
local root = assert(vim.env.BENCH_ROOT)
local output = assert(vim.env.BENCH_OUT)
local result = { server = server, workspace = root, completion_ms = {}, publications = {}, progress = {} }
local function save()
	vim.fn.writefile({ vim.json.encode(result) }, output)
end
local function check(ok, message)
	if not ok then
		result.error = message
		save()
		error(message)
	end
end
-- Load the production LSP setup before overriding its server, just as the
-- integration runner does; otherwise BufReadPre would replace our handlers.
vim.api.nvim_exec_autocmds("BufReadPre", {})
require("lz.n").trigger_load("lazydev.nvim")
vim.opt.swapfile = false
vim.opt.undofile = false
vim.lsp.enable("lua_ls", false)
vim.lsp.enable("emmylua_ls", false)
local target = root .. "/lua/mayon/lsp/servers.lua"
local last_event = uv.hrtime()
local pending = {}
local first_publish
local measured_client
local probe_line
local function lsp_diagnostics()
	if not measured_client then
		return {}
	end
	local diagnostics = {}
	for _, pull in ipairs({ false, true }) do
		vim.list_extend(
			diagnostics,
			vim.diagnostic.get(0, {
				namespace = vim.lsp.diagnostic.get_namespace(measured_client.id, pull),
			})
		)
	end
	return diagnostics
end
vim.api.nvim_create_autocmd("DiagnosticChanged", {
	callback = function(event)
		if event.buf ~= vim.api.nvim_get_current_buf() then
			return
		end
		local found = lsp_diagnostics()
		for _, d in ipairs(found) do
			if d.lnum == probe_line then
				first_publish = first_publish or ms()
				last_event = uv.hrtime()
			end
		end
	end,
})
local handler = vim.lsp.handlers["textDocument/publishDiagnostics"]
local capabilities = vim.deepcopy(vim.lsp.config.lua_ls.capabilities)
-- Use push diagnostics in both servers. Headless startup does not run the
-- interactive pull refresh cycle; removing the capability also avoids mixing
-- push and pull namespaces or counting duplicate results.
capabilities.textDocument.diagnostic = nil
local config = {
	name = server,
	capabilities = capabilities,
	before_init = function(params)
		-- Client.create adds default capabilities again, so remove this at the
		-- final initialization boundary rather than only from config.capabilities.
		params.capabilities.textDocument.diagnostic = nil
	end,
	cmd = { assert(vim.env.BENCH_CMD) },
	root_dir = root,
	filetypes = { "lua" },
	settings = {
		Lua = {
			runtime = { version = "LuaJIT" },
			diagnostics = { globals = { "vim" } },
			workspace = { checkThirdParty = false },
		},
	},
	handlers = {
		["textDocument/publishDiagnostics"] = function(err, params, ctx, opts)
			if params.uri == vim.uri_from_fname(target) then
				result.publications[#result.publications + 1] = { ms = ms(), count = #params.diagnostics }
			end
			last_event = uv.hrtime()
			return handler(err, params, ctx, opts)
		end,
	},
}
vim.api.nvim_create_autocmd("LspProgress", {
	callback = function(event)
		local params = event.data.params
		local value = params.value
		if type(value) ~= "table" then
			return
		end
		if value.kind == "begin" then
			pending[params.token] = true
		elseif value.kind == "end" then
			pending[params.token] = nil
		end
		last_event = uv.hrtime()
		result.progress[#result.progress + 1] =
			{ ms = ms(), kind = value.kind, title = value.title, message = value.message }
	end,
})
-- lazydev adds this Neovim config's lua/ as a library and excludes it from
-- the main workspace. Emmy skips diagnostics for library files entirely.
-- Preserve lazydev's external libraries, but keep our measured code in the
-- main workspace for BOTH servers, with equivalent local module search paths.
local lazydev_lsp = require("lazydev.lsp")
local original_configuration = lazydev_lsp.on_workspace_configuration
lazydev_lsp.on_workspace_configuration = function(...)
	local responses = original_configuration(...)
	for index, value in ipairs(responses) do
		if type(value) == "table" and value.workspace then
			local settings = vim.deepcopy(value)
			settings.workspace.library = vim.tbl_filter(function(path)
				return path ~= root .. "/lua"
			end, settings.workspace.library or {})
			settings.workspace.ignoreDir = vim.tbl_filter(function(path)
				return path ~= "/lua"
			end, settings.workspace.ignoreDir or {})
			settings.runtime = settings.runtime or {}
			settings.runtime.path = { "?.lua", "?/init.lua", "lua/?.lua", "lua/?/init.lua" }
			responses[index] = settings
			result.effective_settings = settings
		end
	end
	return responses
end
vim.cmd.edit(vim.fn.fnameescape(target))
-- LuaLS does not publish an initial empty diagnostic list. A known undefined
-- global in the in-memory buffer guarantees a completed pass is observable.
-- Never write this probe to the workspace, and exclude it from quality counts.
probe_line = vim.api.nvim_buf_line_count(0) - 1
vim.api.nvim_buf_set_lines(0, probe_line, probe_line, false, { "vim.g.r10_probe = __r10_missing_symbol" })
vim.lsp.start(config)
check(
	vim.wait(120000, function()
		return #vim.lsp.get_clients({ bufnr = 0, name = server }) > 0
	end, 10),
	"attach timeout"
)
local client = vim.lsp.get_clients({ bufnr = 0, name = server })[1]
measured_client = client
result.attach_ms = ms()
result.handler_matches = client.config.handlers["textDocument/publishDiagnostics"]
	== config.handlers["textDocument/publishDiagnostics"]
result.client_root = client.config.root_dir
result.clients = vim.tbl_map(function(c)
	return c.name
end, vim.lsp.get_clients())
save()
-- Servers expose no universal "all diagnostics finished" notification. Use the
-- first target publication, ended progress, then 2s without diagnostics/progress.
check(
	vim.wait(120000, function()
		return first_publish ~= nil and next(pending) == nil and (uv.hrtime() - last_event) > 2e9
	end, 20),
	"diagnostics timeout"
)
result.first_diagnostics_ms = first_publish
result.diagnostics_settled_ms = ms() - 2000
result.all_diagnostics = lsp_diagnostics()
result.probe_detected = false
result.diagnostics = {}
for _, d in ipairs(result.all_diagnostics) do
	if d.lnum == probe_line then
		result.probe_detected = true
	else
		result.diagnostics[#result.diagnostics + 1] = d
	end
end
check(result.probe_detected, "server did not diagnose the known probe")
check(result.effective_settings ~= nil, "lazydev settings were not requested")
check(
	not vim.tbl_contains(result.effective_settings.workspace.library, root .. "/lua"),
	"local source was classified as a library"
)
check(not vim.tbl_contains(result.effective_settings.workspace.ignoreDir, "/lua"), "local source was excluded")
result.all_diagnostics = nil
for _, d in ipairs(result.diagnostics) do
	d.bufnr = nil
	d.namespace = nil
	d.user_data = nil
	d._extmark_id = nil
end
result.lazydev_attached = require("lazydev.lsp").attached[client.id] ~= nil
local ws = require("lazydev.workspace").find({ buf = 0 })
result.library = ws.library
result.settings = ws.settings
local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
local row, column
for i, line in ipairs(lines) do
	local a = line:find("vim.lsp.config", 1, true)
	if a then
		row = i - 1
		column = a + #"vim.lsp." - 1
		break
	end
end
check(row ~= nil, "completion position missing")
result.completion_position = { line = row, character = column }
result.completion_items = {}
for _ = 1, 10 do
	local before = uv.hrtime()
	local response = client:request_sync("textDocument/completion", {
		textDocument = { uri = vim.uri_from_fname(target) },
		position = result.completion_position,
		context = { triggerKind = 1 },
	}, 30000, 0)
	local elapsed = (uv.hrtime() - before) / 1e6
	check(response and not response.err, "completion failed: " .. vim.inspect(response))
	local items = response.result and (response.result.items or response.result) or {}
	check(#items > 0, "completion result was empty")
	result.completion_ms[#result.completion_ms + 1] = elapsed
	result.completion_items[#result.completion_items + 1] = #items
end
if vim.env.BENCH_QUALITY == "1" then
	result.quality = {}
	for _, relative in ipairs({
		"init.lua",
		"lua/mayon/config/bootstrap.lua",
		"lua/mayon/lsp/servers.lua",
		"lua/mayon/ui/dashboard.lua",
		"lua/mayon/plugins/lua.lua",
		"lua/mayon/plugins/completion.lua",
		"lua/mayon/plugins/ai.lua",
		"tests/lua_workspace.lua",
	}) do
		vim.cmd("hide edit " .. vim.fn.fnameescape(root .. "/" .. relative))
		local buf = vim.api.nvim_get_current_buf()
		-- Restore any earlier in-memory probe before adding a probe at the top.
		local original = vim.fn.readfile(root .. "/" .. relative)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, original)
		probe_line = 0
		first_publish = nil
		last_event = uv.hrtime()
		vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "vim.g.r10_probe = __r10_missing_symbol" })
		vim.lsp.buf_attach_client(buf, client.id)
		check(
			vim.wait(30000, function()
				return first_publish ~= nil and next(pending) == nil and uv.hrtime() - last_event > 2e9
			end, 20),
			"quality diagnostics timeout: " .. relative
		)
		local entry = { file = relative, diagnostics = {}, probe_detected = false }
		for _, d in ipairs(lsp_diagnostics()) do
			if d.lnum == 0 then
				entry.probe_detected = true
			else
				entry.diagnostics[#entry.diagnostics + 1] = {
					lnum = d.lnum - 1,
					col = d.col,
					code = d.code,
					source = d.source,
					message = d.message,
					severity = d.severity,
				}
			end
		end
		check(entry.probe_detected, "quality probe missing: " .. relative)
		result.quality[#result.quality + 1] = entry
	end
end
save()
client:stop(true)
vim.cmd("qa!")
