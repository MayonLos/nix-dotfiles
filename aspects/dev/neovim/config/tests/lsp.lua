local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fs.dirname(vim.fs.dirname(source))
vim.opt.rtp:prepend(root)
if vim.env.NVIM_LSPCONFIG_PATH then
	vim.opt.rtp:prepend(vim.env.NVIM_LSPCONFIG_PATH)
end

-- --clean intentionally skips bootstrap. Load the optional payloads that
-- production's lz.n language spec now supplies before native LSP setup.
vim.cmd.packadd("nvim-lspconfig")
local lsp = require("mayon.lsp")
lsp.setup()
require("mayon.config.keymaps").setup()

local configs = require("mayon.lsp.servers").servers
assert(vim.tbl_count(configs) == 17, "expected all 17 LSP servers")
assert(vim.bo.filetype == "", "test expects an empty current buffer")
assert(vim.diagnostic.config().virtual_text == false)
assert(vim.diagnostic.config().virtual_lines == false)
assert(vim.diagnostic.config().severity_sort == true)
assert(not vim.lsp.inlay_hint.is_enabled({ bufnr = 0 }), "inlay hints should default to off")
local inlay_toggle = vim.fn.maparg("<leader>uh", "n", false, true)
assert(type(inlay_toggle.callback) == "function", "inlay hint toggle mapping is missing")
inlay_toggle.callback()
assert(vim.lsp.inlay_hint.is_enabled({ bufnr = 0 }), "inlay hint toggle should enable hints")
inlay_toggle.callback()
assert(not vim.lsp.inlay_hint.is_enabled({ bufnr = 0 }), "inlay hint toggle should disable hints")

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
assert(
	vim.deep_equal(vim.lsp.config["*"].capabilities, vim.lsp.protocol.make_client_capabilities()),
	"LSP servers should use native Neovim capabilities"
)

local bufnr = vim.api.nvim_get_current_buf()
local get_client_by_id = vim.lsp.get_client_by_id
vim.lsp.get_client_by_id = function(id)
	if id == -1 then
		return {
			id = id,
			supports_method = function()
				return false
			end,
		}
	end
	return get_client_by_id(id)
end
vim.api.nvim_exec_autocmds("LspAttach", { buffer = bufnr, data = { client_id = -1 } })
vim.lsp.get_client_by_id = get_client_by_id
local maps = {}
for _, keymap in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "n")) do
	maps[keymap.desc] = true
end
for _, desc in ipairs({
	"跳到定义",
	"跳到声明",
	"跳到类型定义",
	"跳到实现",
	"查看悬浮文档",
	"运行代码透镜",
	"重命名符号",
	"执行代码动作",
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
assert(global_maps["切换源文件与头文件"], "source/header map should remain global")
assert(not vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }), "LspAttach should keep inlay hints disabled")

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
	assert(not vim.lsp.inlay_hint.is_enabled({ bufnr = cssbuf }), "LspAttach should keep inlay hints disabled")
	print("CSS LSP attached and reported an unsaved diagnostic")
end

print("LSP Lua configuration checks passed")
