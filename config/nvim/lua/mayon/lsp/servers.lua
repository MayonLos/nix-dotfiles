local M = {}

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

local servers = {
	clangd = {
		cmd = { "clangd", "--background-index", "--clang-tidy" },
		filetypes = { "c", "cpp", "objc", "objcpp", "cuda" },
		root_markers = { "compile_commands.json", ".clangd", "CMakeLists.txt", ".git" },
	},
	dockerls = {
		cmd = { "docker-langserver", "--stdio" },
		filetypes = { "dockerfile" },
		root_markers = { ".git" },
	},
	nixd = {
		cmd = { "nixd" },
		filetypes = { "nix" },
		root_markers = { "flake.nix", ".git" },
		settings = { nixd = { formatting = { command = { "nixfmt" } } } },
	},
	lua_ls = {
		cmd = { "lua-language-server" },
		filetypes = { "lua" },
		root_markers = { ".luarc.json", ".luarc.jsonc", ".stylua.toml", ".git" },
		settings = {
			Lua = {
				runtime = { version = "LuaJIT" },
				diagnostics = { globals = { "vim" } },
				workspace = { library = vim.api.nvim_get_runtime_file("", true) },
			},
		},
	},
	pyright = {
		cmd = { "pyright-langserver", "--stdio" },
		filetypes = { "python" },
		root_markers = {
			"pyproject.toml",
			"pyrightconfig.json",
			"uv.lock",
			"setup.py",
			"setup.cfg",
			"requirements.txt",
			".git",
		},
		before_init = python_path,
		settings = {
			python = {
				analysis = {
					autoSearchPaths = true,
					useLibraryCodeForTypes = true,
					autoImportCompletions = true,
					diagnosticMode = "openFilesOnly",
					typeCheckingMode = "basic",
				},
			},
		},
	},
	jdtls = {
		cmd = { "jdtls" },
		filetypes = { "java" },
		root_markers = { "pom.xml", "build.gradle", "settings.gradle", ".git" },
	},
	bashls = {
		cmd = { "bash-language-server", "start" },
		filetypes = { "bash", "sh" },
		root_markers = { ".git" },
	},
	texlab = {
		cmd = { "texlab" },
		filetypes = { "tex", "plaintex", "bib" },
		root_markers = { ".latexmkrc", ".git" },
		settings = {
			texlab = {
				bibtexFormatter = "texlab",
				chktex = { onOpenAndSave = true, onEdit = false },
				diagnosticsDelay = 300,
				formatterLineLength = 100,
				inlayHints = { labelDefinitions = true, labelReferences = true },
			},
		},
	},
	marksman = {
		cmd = { "marksman", "server" },
		filetypes = { "markdown" },
		root_markers = { ".marksman.toml", ".git" },
		handlers = { ["textDocument/publishDiagnostics"] = marksman_diagnostics },
	},
	matlab_ls = {
		cmd = { "matlab-ls" },
		filetypes = { "matlab" },
		root_markers = { ".git" },
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
	cmake = {
		cmd = { "cmake-language-server" },
		filetypes = { "cmake" },
		root_markers = { "CMakeLists.txt", "CMakePresets.json", ".git" },
	},
	html = {
		cmd = { "vscode-html-language-server", "--stdio" },
		filetypes = { "html", "templ" },
		root_markers = { "package.json", ".git" },
	},
	cssls = {
		cmd = { "vscode-css-language-server", "--stdio" },
		filetypes = { "css", "scss", "less" },
		root_markers = { "package.json", ".git" },
	},
	jsonls = {
		cmd = { "vscode-json-language-server", "--stdio" },
		filetypes = { "json", "jsonc" },
		root_markers = { "package.json", ".git" },
	},
	ts_ls = {
		cmd = { "typescript-language-server", "--stdio" },
		filetypes = { "javascript", "javascriptreact", "typescript", "typescriptreact" },
		root_markers = { "tsconfig.json", "jsconfig.json", "package.json", ".git" },
	},
	yamlls = {
		cmd = { "yaml-language-server", "--stdio" },
		filetypes = { "yaml" },
		root_markers = { ".git" },
		settings = { yaml = { schemaStore = { enable = false } } },
	},
}

function M.setup()
	vim.filetype.add({ extension = { mdx = "markdown" } })

	local capabilities = vim.lsp.protocol.make_client_capabilities()
	local ok, blink = pcall(require, "blink.cmp")
	if ok and type(blink.get_lsp_capabilities) == "function" then
		capabilities = blink.get_lsp_capabilities(capabilities)
	end

	vim.lsp.config("*", { capabilities = capabilities })
	for name, config in pairs(servers) do
		vim.lsp.config(name, config)
	end
	vim.lsp.enable(vim.tbl_keys(servers))
end

M.servers = servers
return M
