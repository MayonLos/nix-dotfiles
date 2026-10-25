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
assert(vim.tbl_count(configs) == 18, "expected all generated LSP servers, including Ruff")
local available_optional = require("mayon.lsp.servers").available_optional
assert(vim.tbl_count(available_optional(function()
	return 0
end)) == 0, "Rust and Go servers must stay disabled when absent from PATH")
local available_from_path = available_optional(function()
	return 1
end)
assert(available_from_path.rust_analyzer and available_from_path.gopls, "Rust and Go should enable when available")
assert(vim.bo.filetype == "", "test expects an empty current buffer")
assert(vim.diagnostic.config().virtual_text == false)
assert(vim.diagnostic.config().virtual_lines == false)
assert(vim.diagnostic.config().severity_sort == true)
assert(vim.diagnostic.config().signs.text[vim.diagnostic.severity.WARN] == "•", "LSP must install the quiet gutter")
assert(not vim.lsp.inlay_hint.is_enabled({ bufnr = 0 }), "inlay hints should default to off")

local inlay_toggle = vim.fn.maparg("<leader>uh", "n", false, true)
assert(type(inlay_toggle.callback) == "function", "inlay hint toggle mapping is missing")
inlay_toggle.callback()
assert(vim.lsp.inlay_hint.is_enabled({ bufnr = 0 }), "inlay hint toggle should enable hints")
inlay_toggle.callback()
assert(not vim.lsp.inlay_hint.is_enabled({ bufnr = 0 }), "inlay hint toggle should disable hints")

local lua_servers = require("mayon.lsp.servers")
local lua_before_init = lua_servers._lua_ls_before_init
local config_root = require("mayon.features.lua_workspace").roots()[1]
local config_settings = {
	root_dir = config_root,
	settings = { Lua = { workspace = { library = { "/managed/config/library" } } } },
}
lua_before_init(nil, config_settings)
assert(config_settings.settings.Lua.runtime.version == "LuaJIT", "managed Neovim config should use LuaJIT")
assert(
	vim.deep_equal(config_settings.settings.Lua.diagnostics.globals, { "vim", "Snacks" }),
	"managed Neovim config should scope vim and Snacks globals to its own workspace"
)
assert(
	config_settings.settings.Lua.workspace.checkThirdParty == false
		and vim.tbl_contains(config_settings.settings.Lua.workspace.library, "/managed/config/library"),
	"managed LuaLS settings should preserve workspace libraries while disabling third-party prompts"
)

-- A project-owned .luarc is authoritative even if it sits at the editor config
-- root; simulate that root without writing into the active checkout.
local old_config_dir = vim.env.NVIM_CONFIG_DIR
local project_root = vim.fn.tempname()
vim.fn.mkdir(project_root, "p")
local luarc = project_root .. "/.luarc.json"
vim.fn.writefile({ '{ "runtime.version": "Lua 5.2" }' }, luarc)
vim.env.NVIM_CONFIG_DIR = project_root
local project_settings = {
	root_dir = project_root,
	settings = {
		Lua = {
			runtime = { version = "Lua 5.2" },
			diagnostics = { globals = { "computer" } },
			workspace = { library = { project_root .. "/lua" }, checkThirdParty = true },
		},
	},
}
local expected_project_settings = vim.deepcopy(project_settings.settings)
lua_before_init(nil, project_settings)
assert(
	vim.deep_equal(project_settings.settings, expected_project_settings),
	"a project-owned .luarc at the Neovim config root must not be overridden"
)
local nested_config = project_root .. "/editor/config"
vim.fn.mkdir(nested_config, "p")
vim.env.NVIM_CONFIG_DIR = nested_config
local inherited = { root_dir = nested_config, settings = {} }
lua_before_init(nil, inherited)
assert(vim.deep_equal(inherited.settings, {}), "an ancestor project .luarc must prevent editor settings injection")
local inherited_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(inherited_buf, nested_config .. "/settings.lua")
local selected_root
vim.lsp.config.lua_ls.root_dir(inherited_buf, function(root)
	selected_root = root
end)
assert(selected_root == project_root, "LuaLS must use the ancestor .luarc directory as its actual root")
vim.api.nvim_buf_delete(inherited_buf, { force = true })
vim.env.NVIM_CONFIG_DIR = old_config_dir
vim.fn.delete(project_root, "rf")
assert(
	vim.tbl_get(vim.lsp.config.lua_ls.settings, "Lua", "runtime") == nil
		and vim.tbl_get(vim.lsp.config.lua_ls.settings, "Lua", "diagnostics", "globals") == nil
		and vim.tbl_get(vim.lsp.config.lua_ls.settings, "Lua", "workspace", "library") == nil,
	"LuaLS base config must not set global project-sensitive settings"
)
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
assert(vim.lsp.config.basedpyright.settings.basedpyright.analysis.typeCheckingMode == "standard")
assert(
	vim.lsp.config.basedpyright.settings.basedpyright.analysis.diagnosticSeverityOverrides.reportUnusedImport == "none"
)
assert(vim.lsp.config.basedpyright.root_markers[1] == "pyrightconfig.json")
assert(vim.lsp.config.basedpyright.root_markers[2] == "pyproject.toml")
assert(vim.lsp.config.ruff.cmd[1] == "ruff" and vim.lsp.config.ruff.cmd[2] == "server")
assert(vim.lsp.config.ruff.init_options.settings.lineLength == 100)
assert(vim.tbl_contains(vim.lsp.config.ruff.init_options.settings.lint.ignore, "F821"))
assert(not vim.tbl_contains(require("mayon.generated").languages.linters.python or {}, "ruff"))
assert(vim.tbl_contains(require("mayon.generated").languages.formatters.python, "ruff_format"))
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

local nixd_before_init = vim.lsp.config.nixd.before_init
local generated_nix_options = require("mayon.generated").nix_options or {}
local nixd_options_for_repository = require("mayon.lsp.servers")._nixd_options_for_repository
local nixd_test_root = vim.fn.tempname()
vim.fn.mkdir(nixd_test_root, "p")
local nixd_config = { root_dir = generated_nix_options.flake or nixd_test_root, settings = {} }
nixd_options_for_repository(nixd_config, generated_nix_options)
if generated_nix_options.flake and generated_nix_options.host then
	local flake_expr = string.format("(builtins.getFlake %q)", generated_nix_options.flake)
	assert(
		nixd_config.settings.nixd.options.nixos.expr
			== flake_expr .. ".nixosConfigurations." .. generated_nix_options.host .. ".options"
	)
	assert(nixd_config.settings.nixd.options.home_manager.expr:find("home%-manager.users.type.getSubOptions"))
	assert(
		nixd_config.settings.nixd.nixpkgs.expr
			== flake_expr .. ".nixosConfigurations." .. generated_nix_options.host .. ".pkgs"
	)
elseif generated_nix_options.flake then
	assert(nixd_config.settings.nixd.nixpkgs.expr:find("inputs.nixpkgs", 1, true))
	assert(not nixd_config.settings.nixd.options, "standalone installs without a host must not inherit host options")
else
	assert(not nixd_config.settings.nixd, "missing host binding must leave generic nixd settings untouched")
end
local other_project_nixd = { root_dir = "/workspace/other-project", settings = {} }
nixd_options_for_repository(other_project_nixd, generated_nix_options.flake and generated_nix_options or {
	flake = nixd_test_root,
	host = "nixos-btw",
})
assert(not other_project_nixd.settings.nixd, "host-specific nixd options must not leak into other projects")
local local_options = { flake = nixd_test_root, host = "nixos-btw" }
local local_nixd = { root_dir = nixd_test_root, settings = {} }
nixd_options_for_repository(local_nixd, local_options)
local local_flake_expr = string.format("(builtins.getFlake %q)", nixd_test_root)
assert(
	local_nixd.settings.nixd.options.nixos.expr == local_flake_expr .. ".nixosConfigurations.nixos-btw.options",
	"repository-local nixd options should point to the selected NixOS host"
)
assert(
	local_nixd.settings.nixd.options.home_manager.expr
		== local_flake_expr .. ".nixosConfigurations.nixos-btw.options.home-manager.users.type.getSubOptions []",
	"repository-local nixd options should expose Home Manager module options"
)

assert(vim.lsp.config.texlab.settings.texlab.build.onSave == false, "LaTeX save-build should be opt-in")
assert(vim.lsp.config.texlab.settings.texlab.forwardSearch.executable == "zathura")
local texlab_runtime = { settings = vim.deepcopy(vim.lsp.config.texlab.settings) }
vim.lsp.config.texlab.before_init(nil, texlab_runtime)
local texlab_args = texlab_runtime.settings.texlab.forwardSearch.args
assert(vim.tbl_contains(texlab_args, "--synctex-editor-command"), "Zathura needs a reverse SyncTeX command")
local reverse_command = texlab_args[vim.fn.index(texlab_args, "--synctex-editor-command") + 2]
assert(reverse_command:find("--server", 1, true) and reverse_command:find("--remote-expr", 1, true))
assert(reverse_command:find("%%{line}") and reverse_command:find("%%{input}"), "Zathura placeholders must be preserved")
assert(
	reverse_command:find("_A%[1%]") and reverse_command:find("_A%[2%]"),
	"reverse SyncTeX should read both array args"
)
assert(reverse_command:find("return true", 1, true), "reverse SyncTeX luaeval must be one valid expression")
assert(reverse_command:find(vim.v.progpath, 1, true), "reverse SyncTeX must use the current Neovim executable")
if vim.v.servername ~= "" then
	assert(reverse_command:find(vim.v.servername, 1, true), "reverse SyncTeX must target this Neovim instance")
end
assert(vim.fn.executable(vim.v.progpath) == 1, "SyncTeX RPC regression needs the current Neovim executable")
local sync_file = vim.fn.tempname() .. " SyncTeX source.tex"
vim.fn.writefile({ "one", "two", "three", "four" }, sync_file)
local original_buf = vim.api.nvim_get_current_buf()
local hold_buf = vim.api.nvim_create_buf(true, false)
local hold_file = vim.fn.tempname() .. " SyncTeX hold.txt"
vim.api.nvim_buf_set_name(hold_buf, hold_file)
vim.api.nvim_set_current_buf(hold_buf)
local rpc_command = reverse_command:gsub("%%{input}", sync_file):gsub("%%{line}", "3")
local remote_exit, remote_stdout, remote_stderr
local remote_job = vim.fn.jobstart({ "sh", "-c", rpc_command }, {
	stdout_buffered = true,
	stderr_buffered = true,
	on_stdout = function(_, data)
		remote_stdout = data
	end,
	on_stderr = function(_, data)
		remote_stderr = data
	end,
	on_exit = function(_, code)
		remote_exit = code
	end,
})
assert(remote_job > 0, "could not start isolated nvim --remote-expr client")
assert(
	vim.wait(10000, function()
		return remote_exit ~= nil
	end, 10),
	"nvim --remote-expr client timed out"
)
assert(remote_exit == 0, "nvim --remote-expr failed: " .. vim.inspect({ remote_exit, remote_stdout, remote_stderr }))
local sync_buf = vim.api.nvim_get_current_buf()
assert(vim.api.nvim_buf_get_name(sync_buf) == sync_file, "SyncTeX RPC should open a source path containing spaces")
assert(vim.api.nvim_win_get_cursor(0)[1] == 3, "SyncTeX RPC should jump to the requested line")
vim.api.nvim_set_current_buf(original_buf)
vim.api.nvim_buf_delete(sync_buf, { force = true })
vim.api.nvim_buf_delete(hold_buf, { force = true })
vim.fn.delete(sync_file)
vim.fn.delete(hold_file)

local folds = require("mayon.features.folds")
local fold_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(fold_buf, 0, -1, false, {
	"  local function example()",
	"    local value = 1",
	"    return value",
	"  end",
	"outside",
})
vim.api.nvim_set_current_buf(fold_buf)
vim.wo.foldmethod = "manual"
vim.wo.foldenable = true
vim.wo.foldtext = "v:lua.require'mayon.features.folds'.text()"
vim.cmd.normal({ "zf2j", bang = true })
assert(vim.fn.foldclosed(1) == 1, "fold summary test must exercise a closed fold")
local rendered_fold = vim.fn.foldtextresult(1)
assert(rendered_fold:find("local function example", 1, true), "foldtextresult should render the fold header")
assert(rendered_fold:find("… 3 lines", 1, true), "foldtextresult should render its capsule line count")
assert(not rendered_fold:find("%#", 1, true), "foldtextresult must not expose highlight markup literally")
vim.api.nvim_set_current_buf(original_buf)
vim.api.nvim_buf_delete(fold_buf, { force = true })
assert(vim.lsp.config.clangd.cmd[2] == "--background-index")
for _, flag in ipairs({
	"--clang-tidy",
	"--header-insertion=never",
	"--completion-style=detailed",
	"--function-arg-placeholders=0",
}) do
	assert(vim.tbl_contains(vim.lsp.config.clangd.cmd, flag), "clangd is missing " .. flag)
end
for _, command in ipairs({ "TexlabBuild", "TexlabForwardSearch", "TexlabClean", "TexlabToggleBuildOnSave" }) do
	assert(vim.api.nvim_get_commands({})[command], "missing public LaTeX command: " .. command)
end
vim.cmd.TexlabToggleBuildOnSave()
assert(vim.lsp.config.texlab.settings.texlab.build.onSave, "LaTeX save-build toggle should enable compilation")
vim.cmd.TexlabToggleBuildOnSave()
assert(not vim.lsp.config.texlab.settings.texlab.build.onSave, "LaTeX save-build toggle should disable compilation")
for _, lhs in ipairs({ ",ll", ",lv", ",lc" }) do
	assert(vim.fn.maparg(lhs, "n") ~= "", "missing LaTeX localleader mapping " .. lhs)
end

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
assert(global_maps[" ch"], "clangd source/header shortcut should be <leader>ch")
assert(not vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }), "LspAttach should keep inlay hints disabled")

local ns = vim.api.nvim_create_namespace("lsp-migration-test")
vim.diagnostic.set(
	ns,
	bufnr,
	{ { lnum = 0, col = 0, message = "unsaved test diagnostic", severity = vim.diagnostic.severity.ERROR } }
)
assert(#vim.diagnostic.get(bufnr, { namespace = ns }) == 1, "diagnostics should be visible before saving")

local switch_mapping = vim.fn.maparg(" ch", "n", false, true)
assert(type(switch_mapping.callback) == "function", "<leader>ch should invoke clangd source/header switching")
local switched_header = vim.fn.tempname() .. ".h"
vim.fn.writefile({ "// clangd switch target" }, switched_header)
local original_get_clients = vim.lsp.get_clients
vim.lsp.get_clients = function(opts)
	if opts and opts.name == "clangd" then
		return {
			{
				name = "clangd",
				request = function(_, method, _, callback)
					assert(method == "textDocument/switchSourceHeader")
					callback(nil, vim.uri_from_fname(switched_header))
					return true
				end,
			},
		}
	end
	return original_get_clients(opts)
end
switch_mapping.callback()
vim.lsp.get_clients = original_get_clients
assert(vim.api.nvim_buf_get_name(0) == switched_header, "clangd shortcut should edit the returned header")
vim.api.nvim_set_current_buf(bufnr)

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
