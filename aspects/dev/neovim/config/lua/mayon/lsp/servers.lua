local M = {}
local nix_options = require("mayon.generated").nix_options or {}

local function nixd_options_for_repository(config, options)
	options = options or nix_options
	local root = options.flake
	local host = options.host
	if not root or root == "" then
		return
	end
	local project = config.root_dir
	if not project then
		return
	end
	root = vim.uv.fs_realpath(root) or vim.fs.normalize(vim.fn.expand(root))
	project = vim.uv.fs_realpath(project) or vim.fs.normalize(project)
	if project ~= root and project:sub(1, #root + 1) ~= root .. "/" then
		return
	end
	local flake = string.format("(builtins.getFlake %q)", root)
	config.settings = config.settings or {}
	config.settings.nixd = config.settings.nixd or {}
	if host and host ~= "" then
		config.settings.nixd.nixpkgs = { expr = flake .. ".nixosConfigurations." .. host .. ".pkgs" }
		config.settings.nixd.options = {
			nixos = { expr = flake .. ".nixosConfigurations." .. host .. ".options" },
			home_manager = {
				expr = flake .. ".nixosConfigurations." .. host .. ".options.home-manager.users.type.getSubOptions []",
			},
		}
	else
		config.settings.nixd.nixpkgs = { expr = "import (" .. flake .. ").inputs.nixpkgs { }" }
	end
end

M._nixd_options_for_repository = nixd_options_for_repository

local function ruff_on_attach(client)
	-- Ruff owns lint diagnostics and import actions; basedpyright owns types.
	-- Remove only Ruff's overlapping navigation/documentation handlers.
	client.server_capabilities.hoverProvider = false
	client.server_capabilities.definitionProvider = false
end

local lua_workspace = require("mayon.features.lua_workspace")

local function lua_ls_root_dir(bufnr, on_dir)
	local filename = vim.api.nvim_buf_get_name(bufnr)
	local directory = vim.fs.dirname(filename)
	local project_config =
		vim.fs.find({ ".luarc.json", ".luarc.jsonc" }, { path = directory, upward = true, type = "file", limit = 1 })[1]
	if project_config then
		on_dir(vim.fs.dirname(project_config))
		return
	end
	local config_root = lua_workspace.root_for_path(filename)
	if config_root then
		on_dir(config_root)
		return
	end
	local root_markers = require("mayon.generated").languages.servers.lua_ls.root_markers
	local root = vim.fs.root(directory, root_markers) or directory
	on_dir(root)
end

local function lua_ls_before_init(_, config)
	if not config.root_dir or not lua_workspace.is_config_root(config.root_dir) then
		return
	end
	if
		vim.fs.find(
			{ ".luarc.json", ".luarc.jsonc" },
			{ path = config.root_dir, upward = true, type = "file", limit = 1 }
		)[1]
	then
		return
	end
	-- Settings sent by the editor win over a project's .luarc.json. Keep the
	-- editor-specific globals/runtime scoped to this checkout only.
	config.settings = config.settings or {}
	config.settings.Lua = config.settings.Lua or {}
	local lua = config.settings.Lua
	lua.runtime = vim.tbl_deep_extend("force", lua.runtime or {}, { version = "LuaJIT" })
	lua.diagnostics = vim.tbl_deep_extend("force", lua.diagnostics or {}, { globals = { "vim", "Snacks" } })
	lua.workspace = vim.tbl_deep_extend("force", lua.workspace or {}, { checkThirdParty = false })
end

M._lua_ls_before_init = lua_ls_before_init

local function texlab_before_init(_, config)
	local server = vim.v.servername
	if server == "" then
		server = vim.fn.serverstart()
	end
	if not server or server == "" then
		return
	end
	local settings = config.settings and config.settings.texlab
	if not settings then
		return
	end
	settings.forwardSearch = settings.forwardSearch or {}
	settings.forwardSearch.executable = "zathura"
	local inverse = "luaeval('(function() vim.cmd.edit(vim.fn.fnameescape(_A[1])); "
		.. "vim.api.nvim_win_set_cursor(0, {_A[2], 0}); return true end)()', ['%{input}', %{line}])"
	settings.forwardSearch.args = {
		"--synctex-forward",
		"%l:1:%f",
		"--synctex-editor-command",
		("%s --server %s --remote-expr %s"):format(
			vim.fn.shellescape(vim.v.progpath),
			vim.fn.shellescape(server),
			vim.fn.shellescape(inverse)
		),
		"%p",
	}
end

local function python_path(_, config)
	local root = config.root_dir
	local python = root and (root .. "/.venv/bin/python")
	if not python or vim.fn.executable(python) ~= 1 then
		python = vim.env.VIRTUAL_ENV and (vim.env.VIRTUAL_ENV .. "/bin/python")
	end
	if python and vim.fn.executable(python) == 1 then
		config.settings = config.settings or {}
		config.settings.python = config.settings.python or {}
		config.settings.python.pythonPath = python
	end
end

local function marksman_diagnostics(err, result, ctx, config)
	for _, diagnostic in ipairs(result and result.diagnostics or {}) do
		if tostring(diagnostic.code) == "2" then
			diagnostic.severity = vim.lsp.protocol.DiagnosticSeverity.Hint
		end
	end
	return vim.lsp.handlers["textDocument/publishDiagnostics"](err, result, ctx, config)
end

local function matlab_notifications()
	return {
		["matlab/connection/update/server"] = function(_, result)
			local status = result and result.connectionStatus
			if status == "connecting" then
				vim.notify("MATLAB starting -- no completion yet", vim.log.levels.INFO, { title = "matlab_ls" })
			elseif status == "connected" then
				vim.notify("MATLAB ready", vim.log.levels.INFO, { title = "matlab_ls" })
			elseif status == "disconnected" then
				vim.notify("MATLAB disconnected", vim.log.levels.WARN, { title = "matlab_ls" })
			end
		end,
		["matlab/launchfailed"] = function()
			vim.notify(
				"MATLAB failed to launch -- check MATLAB_INSTALL_DIR",
				vim.log.levels.ERROR,
				{ title = "matlab_ls" }
			)
		end,
	}
end

local adapters = {
	nixd = {
		before_init = function(_, config)
			nixd_options_for_repository(config)
		end,
		settings = {
			nixd = {
				nixpkgs = { expr = "import <nixpkgs> { }" },
				formatting = { command = { "nixfmt" } },
			},
		},
	},
	lua_ls = {
		root_dir = lua_ls_root_dir,
		before_init = lua_ls_before_init,
	},
	basedpyright = {
		before_init = python_path,
		settings = {
			basedpyright = {
				analysis = {
					autoSearchPaths = true,
					autoImportCompletions = true,
					diagnosticMode = "openFilesOnly",
					typeCheckingMode = "standard",
					diagnosticSeverityOverrides = {
						reportUnusedImport = "none",
						reportUnusedVariable = "none",
						reportUnusedExpression = "none",
					},
				},
			},
		},
	},
	ruff = {
		on_attach = ruff_on_attach,
		init_options = {
			settings = {
				lineLength = 100,
				-- basedpyright owns undefined-name/type diagnostics (F821).
				lint = { enable = true, ignore = { "F821" } },
			},
		},
	},
	texlab = {
		before_init = texlab_before_init,
		settings = {
			texlab = {
				build = {
					onSave = false,
					forwardSearchAfter = false,
					args = { "-pdf", "-interaction=nonstopmode", "-synctex=1", "%f" },
				},
				forwardSearch = {
					executable = "zathura",
					args = { "--synctex-forward", "%l:1:%f", "%p" },
				},
				bibtexFormatter = "texlab",
				chktex = { onOpenAndSave = true, onEdit = false },
				diagnosticsDelay = 300,
				formatterLineLength = 100,
				inlayHints = { labelDefinitions = true, labelReferences = true },
			},
		},
	},
	marksman = {
		handlers = { ["textDocument/publishDiagnostics"] = marksman_diagnostics },
	},
	matlab_ls = {
		settings = {
			MATLAB = {
				installPath = vim.env.MATLAB_INSTALL_DIR or vim.fn.expand("~/.local/share/MATLAB/R2026a"),
				matlabConnectionTiming = "onStart",
				indexWorkspace = true,
				telemetry = false,
			},
		},
		handlers = matlab_notifications(),
	},
	yamlls = {
		settings = { yaml = { schemaStore = { enable = false } } },
	},
}

local servers = vim.deepcopy(require("mayon.generated").languages.servers)
for name, settings in pairs(servers) do
	servers[name] = vim.tbl_deep_extend("force", settings, adapters[name] or {})
end

local optional_servers = {
	rust_analyzer = {
		cmd = { "rust-analyzer" },
		filetypes = { "rust" },
		root_markers = { "Cargo.toml", ".git" },
	},
	gopls = {
		cmd = { "gopls" },
		filetypes = { "go", "gomod", "gowork", "gotmpl" },
		root_markers = { "go.work", "go.mod", ".git" },
	},
}

function M.available_optional(executable)
	local available = {}
	for name, config in pairs(optional_servers) do
		if executable(config.cmd[1]) == 1 then
			available[name] = config
		end
	end
	return available
end

function M.setup()
	vim.filetype.add({ extension = { mdx = "markdown" } })

	vim.lsp.config("*", { capabilities = vim.lsp.protocol.make_client_capabilities() })
	for name, config in pairs(servers) do
		vim.lsp.config(name, config)
	end
	local enabled = vim.tbl_keys(servers)
	for name, config in pairs(M.available_optional(vim.fn.executable)) do
		vim.lsp.config(name, config)
		enabled[#enabled + 1] = name
	end
	vim.lsp.enable(enabled)

	local group = vim.api.nvim_create_augroup("MayonLanguageWorkspaceHints", { clear = true })
	local warned = {}
	vim.api.nvim_create_autocmd("LspAttach", {
		group = group,
		callback = function(event)
			local client = vim.lsp.get_client_by_id(event.data and event.data.client_id)
			if not client or client.name ~= "clangd" then
				return
			end
			local root = client.config.root_dir
			if not root or warned[root] then
				return
			end
			if vim.fn.filereadable(root .. "/compile_commands.json") ~= 1 then
				warned[root] = true
				vim.notify(
					"未找到 compile_commands.json；clangd 可继续工作，建议由 CMake/构建系统生成以获得完整项目索引。",
					vim.log.levels.INFO,
					{ title = "clangd" }
				)
			end
		end,
	})

	local tex_commands = {
		TexlabBuild = { method = "textDocument/build", args = {} },
		TexlabForwardSearch = { method = "textDocument/forwardSearch", args = {} },
		TexlabClean = { command = "texlab.cleanAuxiliary" },
	}
	local function texlab_request(name, params)
		local client = vim.lsp.get_clients({ bufnr = 0, name = "texlab" })[1]
		if not client then
			vim.notify(
				"texlab 尚未连接；请确认已安装 LaTeX support 并打开 .tex 文件。",
				vim.log.levels.WARN
			)
			return
		end
		local action = tex_commands[name]
		if action.method then
			client:request(
				action.method,
				params or { textDocument = vim.lsp.util.make_text_document_params(0) },
				function(err)
					if err then
						vim.notify("texlab: " .. err.message, vim.log.levels.ERROR)
					end
				end,
				0
			)
		else
			client:exec_cmd({ command = action.command, arguments = {} }, { bufnr = 0 }, function(err)
				if err then
					vim.notify("texlab: " .. err.message, vim.log.levels.ERROR)
				end
			end)
		end
	end
	vim.api.nvim_create_user_command("TexlabBuild", function()
		texlab_request("TexlabBuild")
	end, { desc = "Compile the current LaTeX project" })
	vim.api.nvim_create_user_command("TexlabForwardSearch", function()
		local params = vim.lsp.util.make_position_params(0, "utf-16")
		texlab_request("TexlabForwardSearch", params)
	end, { desc = "SyncTeX forward search in Zathura" })
	vim.api.nvim_create_user_command("TexlabClean", function()
		texlab_request("TexlabClean")
	end, { desc = "Remove LaTeX auxiliary files" })
	vim.api.nvim_create_user_command("TexlabToggleBuildOnSave", function()
		local config = vim.lsp.config.texlab
		local build = vim.tbl_get(config, "settings", "texlab", "build")
		build.onSave = not build.onSave
		vim.notify("LaTeX 保存时编译 " .. (build.onSave and "已开启" or "已关闭"), vim.log.levels.INFO)
		for _, client in ipairs(vim.lsp.get_clients({ name = "texlab" })) do
			client:notify("workspace/didChangeConfiguration", { settings = config.settings })
		end
	end, { desc = "Toggle LaTeX build on save" })
	vim.keymap.set("n", ",ll", "<cmd>TexlabBuild<cr>", { desc = "编译 LaTeX", silent = true })
	vim.keymap.set("n", ",lv", "<cmd>TexlabForwardSearch<cr>", { desc = "Zathura SyncTeX 正向搜索", silent = true })
	vim.keymap.set("n", ",lc", "<cmd>TexlabClean<cr>", { desc = "清理 LaTeX 辅助文件", silent = true })
end

M.servers = servers
return M
