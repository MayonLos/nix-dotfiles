local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fs.dirname(vim.fs.dirname(source))
vim.opt.rtp:prepend(root)
if vim.env.NVIM_LSPCONFIG_PATH then
	vim.opt.rtp:prepend(vim.env.NVIM_LSPCONFIG_PATH)
end
if vim.env.NVIM_BLINK_PATH then
	vim.opt.rtp:prepend(vim.env.NVIM_BLINK_PATH)
end

-- --clean intentionally skips bootstrap. Load the optional payloads that
-- production's lz.n language spec now supplies before native LSP setup.
vim.cmd.packadd("nvim-lspconfig")
vim.cmd.packadd("blink.cmp")
local lsp = require("mayon.lsp")
lsp.setup()

local configs = require("mayon.lsp.servers").servers
assert(vim.tbl_count(configs) == 17, "expected all 17 LSP servers")
assert(vim.bo.filetype == "", "test expects an empty current buffer")
assert(vim.diagnostic.config().virtual_text == false)
assert(vim.diagnostic.config().virtual_lines == false)
assert(vim.diagnostic.config().severity_sort == true)

-- LSP startup work can expose several concurrent tokens. Publish only a
-- compact statusline snapshot; routine progress must never create toasts.
do
	local client_id = 987654
	local other_client_id = 987655
	local original_notify = vim.notify
	local original_get_client = vim.lsp.get_client_by_id
	local notifications = {}
	local progress_events = {}
	local event_group = vim.api.nvim_create_augroup("LspProgressTest", { clear = true })
	vim.api.nvim_create_autocmd("User", {
		group = event_group,
		pattern = "MayonLspProgressChanged",
		callback = function(event)
			progress_events[#progress_events + 1] = event.data
		end,
	})
	vim.notify = function(message, level, opts)
		opts = opts or {}
		local id = opts.replace or (#notifications + 1)
		notifications[#notifications + 1] = { id = id, message = message, level = level, opts = opts }
		return id
	end
	vim.lsp.get_client_by_id = function(id)
		if id == client_id then
			return { name = "jdtls", attached_buffers = {} }
		elseif id == other_client_id then
			return { name = "clangd", attached_buffers = {} }
		end
		return original_get_client(id)
	end
	local function emit(id, token, kind, message)
		vim.api.nvim_exec_autocmds("LspProgress", {
			data = {
				client_id = id,
				params = { token = token, value = { kind = kind, title = token, message = message } },
			},
		})
	end
	emit(client_id, "jvm", "begin", "Detect installed JVMs")
	assert(#notifications == 0, "LSP begin progress must not notify")
	assert(#lsp.progress_status() == 1 and lsp.progress_status()[1].name == "jdtls")
	emit(client_id, "sync", "begin", "Synchronizing projects")
	assert(#notifications == 0, "parallel LSP progress must not notify")
	assert(lsp.progress_status()[1].task_count == 2, "parallel tasks should be aggregated for the statusline")
	assert(progress_events[#progress_events][1].task_count == 2, "progress change event should publish the aggregate")
	emit(client_id, "jvm", "report", "Using configured JVM")
	assert(#notifications == 0, "progress reports must not notify")
	assert(
		lsp.progress_status()[1].message:find("Synchronizing projects", 1, true),
		"active parallel task should remain summarized"
	)
	emit(client_id, "jvm", "end", "")
	assert(
		#notifications == 0 and lsp.progress_status()[1].task_count == 1,
		"partial completion should update the aggregate without notifying"
	)
	emit(client_id, "sync", "end", "")
	assert(#notifications == 0, "completed LSP progress must not notify")
	assert(#lsp.progress_status() == 0, "completed progress should leave no stale statusline entry")
	emit(client_id, "restart", "begin", "Restarting language server")
	emit(other_client_id, "index", "begin", "Indexing workspace")
	emit(client_id, "restart", "report", "Loading project")
	local latest = lsp.progress_status()
	assert(#latest == 2 and latest[1].name == "clangd" and latest[2].name == "jdtls")
	emit(client_id, "restart", "end", "")
	assert(#lsp.progress_status() == 1 and lsp.progress_status()[1].name == "clangd")
	-- A synthetic last-client detach resets Neovim buffer-local hint state.
	-- Keep that lifecycle event off the buffer used by the attach tests below.
	local detached_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_exec_autocmds("LspDetach", {
		buffer = detached_buf,
		data = { client_id = other_client_id },
	})
	assert(
		vim.wait(1000, function()
			return #lsp.progress_status() == 0
		end, 10),
		"detaching the last buffer should clear the client's progress status"
	)
	vim.api.nvim_buf_delete(detached_buf, { force = true })
	assert(#notifications == 0, "progress end and detach must never notify")
	assert(progress_events[#progress_events][1] == nil, "cleared status should be published after detach")
	vim.notify = original_notify
	vim.lsp.get_client_by_id = original_get_client
end

assert(vim.lsp.config.lua_ls.settings.Lua.runtime.version == "LuaJIT")
assert(vim.lsp.config.yamlls.settings.yaml.schemaStore.enable == false)
assert(vim.lsp.config.matlab_ls.settings.MATLAB.telemetry == false)
assert(vim.lsp.config.matlab_ls.settings.MATLAB.matlabConnectionTiming == "onStart")
assert(vim.lsp.config.marksman.filetypes[1] == "markdown")
assert(vim.filetype.match({ filename = "note.mdx" }) == "markdown")
local basedpyright_project = vim.fn.tempname()
local basedpyright_python = basedpyright_project .. "/.venv/bin/python"
local other_python = basedpyright_project .. "/other-venv/bin/python"
vim.fn.mkdir(vim.fs.dirname(basedpyright_python), "p")
vim.fn.mkdir(vim.fs.dirname(other_python), "p")
vim.fn.writefile({ "#!/bin/sh", "exit 0" }, basedpyright_python)
vim.fn.writefile({ "#!/bin/sh", "exit 0" }, other_python)
vim.fn.setfperm(basedpyright_python, "rwxr-xr-x")
vim.fn.setfperm(other_python, "rwxr-xr-x")
local old_virtual_env = vim.env.VIRTUAL_ENV
vim.env.VIRTUAL_ENV = vim.fs.dirname(vim.fs.dirname(other_python))
local basedpyright_config = { root_dir = basedpyright_project, settings = {} }
vim.lsp.config.basedpyright.before_init(nil, basedpyright_config)
assert(basedpyright_config.settings.python.pythonPath == basedpyright_python, "project .venv should take priority")
vim.env.VIRTUAL_ENV = old_virtual_env
assert(vim.lsp.config.basedpyright.cmd[1] == "basedpyright-langserver")
assert(vim.lsp.config.basedpyright.settings.basedpyright.analysis.typeCheckingMode == "basic")
assert(vim.lsp.config.basedpyright.root_markers[1] == "pyrightconfig.json")
assert(vim.lsp.config.basedpyright.root_markers[2] == "pyproject.toml")
assert(vim.lsp.config.taplo.cmd[1] == "taplo" and vim.lsp.config.taplo.cmd[2] == "lsp")
assert(vim.lsp.config.taplo.filetypes[1] == "toml")

local original_diagnostics_handler = vim.lsp.handlers["textDocument/publishDiagnostics"]
vim.lsp.handlers["textDocument/publishDiagnostics"] = function(_, result)
	return result
end
local missing_page = { code = "2", severity = vim.diagnostic.severity.ERROR }
vim.lsp.config.marksman.handlers["textDocument/publishDiagnostics"](nil, { diagnostics = { missing_page } }, {}, {})
vim.lsp.handlers["textDocument/publishDiagnostics"] = original_diagnostics_handler
assert(missing_page.severity == vim.diagnostic.severity.HINT, "missing Marksman pages should be hints")
if vim.env.NVIM_BLINK_PATH then
	local blink = require("blink.cmp")
	local expected = blink.get_lsp_capabilities(vim.lsp.protocol.make_client_capabilities())
	assert(
		vim.deep_equal(vim.lsp.config["*"].capabilities, expected),
		"Blink LSP capabilities should be applied globally"
	)
end

local bufnr = vim.api.nvim_get_current_buf()
vim.api.nvim_exec_autocmds("LspAttach", { buffer = bufnr, data = { client_id = -1 } })
local maps = {}
for _, keymap in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
	maps[keymap.desc] = true
end
for _, desc in ipairs({
	"Go to definition",
	"Go to declaration",
	"Type definition",
	"Implementation",
	"Hover",
	"Run codelens",
	"Rename symbol",
	"Code action",
	"Workspace diagnostics",
}) do
	assert(maps[desc], "missing LspAttach map " .. desc)
end
local global_maps = {}
for _, keymap in ipairs(vim.api.nvim_get_keymap("n")) do
	global_maps[keymap.lhs] = true
	if keymap.desc then
		global_maps[keymap.desc] = true
	end
end
for _, lhs in ipairs({ "gra", "gri", "grn", "grr", "grt", "grx" }) do
	assert(global_maps[lhs], "native global LSP map was removed: " .. lhs)
end
assert(global_maps["Switch source/header"], "source/header map should remain global")
assert(vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }), "inlay hints should be enabled for attached buffers")

local ns = vim.api.nvim_create_namespace("lsp-migration-test")
vim.diagnostic.set(
	ns,
	bufnr,
	{ { lnum = 0, col = 0, message = "unsaved test diagnostic", severity = vim.diagnostic.severity.ERROR } }
)
assert(#vim.diagnostic.get(bufnr, { namespace = ns }) == 1, "diagnostics should be visible before saving")

if vim.env.NVIM_LSP_INTEGRATION == "1" then
	local project = vim.fn.tempname()
	vim.fn.mkdir(project, "p")
	vim.fn.writefile({ "{}" }, project .. "/package.json")
	local css = project .. "/style.css"
	vim.fn.writefile({ "a { color: red; }" }, css)
	vim.cmd.filetype("on")
	vim.cmd.edit(css)
	local cssbuf = vim.api.nvim_get_current_buf()
	local attached = vim.wait(20000, function()
		return #vim.lsp.get_clients({ bufnr = cssbuf, name = "cssls" }) > 0
	end, 100)
	if not attached then
		print("cssls enabled:", vim.inspect(vim.lsp.is_enabled("cssls")))
		print("css buffer filetype:", vim.bo[cssbuf].filetype)
		print("cssls config:", vim.inspect(vim.lsp.config.cssls))
		print("LSP log:", vim.lsp.log.get_filename())
	end
	assert(attached, "cssls did not attach")
	vim.api.nvim_buf_set_lines(cssbuf, 0, -1, false, { "a { color: #12; }" })
	assert(
		vim.wait(15000, function()
			return #vim.diagnostic.get(cssbuf) > 0
		end, 100),
		"cssls did not publish diagnostics for unsaved edits"
	)
	assert(vim.bo[cssbuf].modified, "integration diagnostic should be from an unsaved buffer")
	assert(vim.lsp.inlay_hint.is_enabled({ bufnr = cssbuf }), "LspAttach should enable inlay hints")
	print("CSS LSP attached and reported an unsaved diagnostic")
end

print("LSP Lua configuration checks passed")
