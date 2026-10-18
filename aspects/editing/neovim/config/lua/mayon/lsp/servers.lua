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

local adapters = {
	nixd = {
		settings = { nixd = { formatting = { command = { "nixfmt" } } } },
	},
	lua_ls = {
		settings = {
			Lua = {
				runtime = { version = "LuaJIT" },
				diagnostics = { globals = { "vim" } },
				-- lazydev adds only libraries actually used by this workspace.
				workspace = { checkThirdParty = false },
			},
		},
	},
	pyright = {
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
	texlab = {
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
