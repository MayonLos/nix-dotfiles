local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fs.dirname(vim.fs.dirname(source))
vim.opt.rtp:prepend(root)
if vim.env.NVIM_LSPCONFIG_PATH then
	vim.opt.rtp:prepend(vim.env.NVIM_LSPCONFIG_PATH)
end
if vim.env.NVIM_BLINK_PATH then
	vim.opt.rtp:prepend(vim.env.NVIM_BLINK_PATH)
end

require("mayon.lsp").setup()

local configs = require("mayon.lsp.servers").servers
assert(vim.tbl_count(configs) == 16, "expected all 16 LSP servers")
assert(vim.bo.filetype == "", "test expects an empty current buffer")
assert(vim.diagnostic.config().virtual_text == false)
assert(vim.diagnostic.config().virtual_lines.current_line == true)
assert(vim.diagnostic.config().severity_sort == true)
assert(vim.lsp.config.lua_ls.settings.Lua.runtime.version == "LuaJIT")
assert(vim.lsp.config.yamlls.settings.yaml.schemaStore.enable == false)
assert(vim.lsp.config.matlab_ls.settings.MATLAB.telemetry == false)
assert(vim.lsp.config.matlab_ls.settings.MATLAB.matlabConnectionTiming == "onStart")
assert(vim.lsp.config.marksman.filetypes[1] == "markdown")
assert(vim.filetype.match({ filename = "note.mdx" }) == "markdown")
local pyright_project = vim.fn.tempname()
local pyright_python = pyright_project .. "/.venv/bin/python"
local other_python = pyright_project .. "/other-venv/bin/python"
vim.fn.mkdir(vim.fs.dirname(pyright_python), "p")
vim.fn.mkdir(vim.fs.dirname(other_python), "p")
vim.fn.writefile({ "#!/bin/sh", "exit 0" }, pyright_python)
vim.fn.writefile({ "#!/bin/sh", "exit 0" }, other_python)
vim.fn.setfperm(pyright_python, "rwxr-xr-x")
vim.fn.setfperm(other_python, "rwxr-xr-x")
local old_virtual_env = vim.env.VIRTUAL_ENV
vim.env.VIRTUAL_ENV = vim.fs.dirname(vim.fs.dirname(other_python))
local pyright_config = { root_dir = pyright_project, settings = {} }
vim.lsp.config.pyright.before_init(nil, pyright_config)
assert(pyright_config.settings.python.pythonPath == pyright_python, "project .venv should take priority")
vim.env.VIRTUAL_ENV = old_virtual_env

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
