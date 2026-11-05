local M = { state = "" }
local tools = require("mayon.generated").tools
local lua_jobs = {}
local state_listeners = {}

local function stop_lua_job(job)
	if job and lua_jobs[job] then
		pcall(vim.fn.jobstop, job)
		lua_jobs[job] = nil
	end
end

-- Every interactive prompt converges on one cancellation sentinel: an empty or
-- rejected answer returns `dap.ABORT`, so nvim-dap stops asking for more input.
local function abort()
	return require("dap").ABORT
end

local function input(prompt, default, transform, completion)
	return coroutine.create(function(co)
		vim.ui.input({ prompt = prompt, default = default, completion = completion }, function(value)
			local result = value and value ~= "" and (transform and transform(value) or value) or abort()
			vim.schedule(function()
				if coroutine.status(co) == "suspended" then
					coroutine.resume(co, result)
				end
			end)
		end)
	end)
end

function M.python_path(root)
	root = root or vim.fs.root(0, { "pyproject.toml", "setup.py", ".git" }) or vim.fn.getcwd()
	local paths = { root .. "/.venv/bin/python", root .. "/venv/bin/python" }
	if vim.env.VIRTUAL_ENV and vim.env.VIRTUAL_ENV ~= "" then
		paths[#paths + 1] = vim.env.VIRTUAL_ENV .. "/bin/python"
	end
	for _, path in ipairs(paths) do
		if vim.fn.executable(path) == 1 then
			return path
		end
	end
	return tools.python
end

local function program()
	return input("Executable or ELF: ", vim.fn.getcwd() .. "/", function(path)
		return vim.fn.filereadable(path) == 1 and vim.fs.normalize(path) or abort()
	end, "file")
end
local function port(default)
	return function()
		return input("Debug port: ", tostring(default), function(value)
			local number = tonumber(value)
			return number and number % 1 == 0 and number > 0 and number < 65536 and number or abort()
		end)
	end
end
local function address(default)
	return function()
		return input("Remote host:port: ", default, function(value)
			local host, p = value:match("^([%w._%-]+):(%d+)$")
			if not host then
				host, p = value:match("^(%[[%x:]+%]):(%d+)$")
			end
			return host and tonumber(p) > 0 and tonumber(p) < 65536 and value or abort()
		end)
	end
end

-- probe-rs flashes the ELF it is given, so both values are asked for on each
-- launch; the last chip is offered again. Projects can pin them in launch.json.
local last_chip = ""
local function probe_chip()
	return input("probe-rs chip: ", last_chip, function(value)
		if not value:match("^[%w_%-]+$") then
			return abort()
		end
		last_chip = value
		return value
	end)
end
local function probe_cores()
	return input("Firmware ELF: ", vim.fn.getcwd() .. "/", function(path)
		if vim.fn.filereadable(path) ~= 1 then
			return abort()
		end
		return { { coreIndex = 0, programBinary = vim.fs.normalize(path) } }
	end, "file")
end

local function lua_adapter(callback, config)
	if not config.program then
		callback({ type = "server", host = config.host or "127.0.0.1", port = config.port })
		return
	end
	local job = vim.fn.jobstart({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "--embed" }, { rpc = true })
	assert(job > 0, "Failed to launch debug Neovim")
	lua_jobs[job] = true
	local ok, server = pcall(function()
		vim.fn.rpcrequest(
			job,
			"nvim_exec_lua",
			'vim.o.packpath = ...; vim.cmd.packadd("one-small-step-for-vimkind")',
			{ vim.o.packpath }
		)
		return vim.fn.rpcrequest(
			job,
			"nvim_exec_lua",
			'return require("osv").launch({host="127.0.0.1",port=0,output=true})',
			{}
		)
	end)
	if not ok or type(server) ~= "table" or type(server.port) ~= "number" or server.port <= 0 then
		stop_lua_job(job)
		error(ok and "Lua debugger did not open a listener" or server)
	end
	config._mayon_lua_job = job
	callback({ type = "server", host = "127.0.0.1", port = server.port })
end

-- Adapter registry: one data table per adapter so names, commands and launch
-- semantics are declared once and applied verbatim (no per-setup branching).
local adapters = {
	gdb = { type = "executable", command = tools.gdb, args = { "--interpreter=dap", "--quiet", "--nx" } },
	codelldb = {
		type = "server",
		port = "${port}",
		executable = { command = tools.codelldb, args = { "--port", "${port}" } },
	},
	-- Same type name as the probe-rs VS Code extension, so one launch.json serves both.
	["probe-rs-debug"] = {
		type = "server",
		port = "${port}",
		executable = { command = tools.probe_rs, args = { "dap-server", "--port", "${port}", "--single-session" } },
	},
	python = function(callback, config)
		if config.request == "attach" then
			callback({
				type = "server",
				host = config.connect.host,
				port = config.connect.port,
				options = { source_filetype = "python" },
			})
		else
			callback({
				type = "executable",
				command = tools.debugpy_python,
				args = { "-m", "debugpy.adapter" },
				options = { source_filetype = "python" },
			})
		end
	end,
	nlua = lua_adapter,
}

-- nvim-dap evaluates a function option once; call the picker here so `pid`
-- receives the chosen process id rather than the picker itself.
local function pick_process()
	return require("dap.utils").pick_process()
end

local native_configs = {
	{
		name = "C/C++: Launch executable",
		type = "gdb",
		request = "launch",
		program = program,
		cwd = "${workspaceFolder}",
		stopAtBeginningOfMainSubprogram = false,
	},
	{
		name = "C/C++: Attach process",
		type = "gdb",
		request = "attach",
		pid = pick_process,
		cwd = "${workspaceFolder}",
	},
	{
		name = "STM32: Attach OpenOCD / ST-Link",
		type = "gdb",
		request = "attach",
		program = program,
		target = address("127.0.0.1:3333"),
		cwd = "${workspaceFolder}",
	},
	{
		name = "STM32: Flash and debug (probe-rs)",
		type = "probe-rs-debug",
		request = "launch",
		cwd = "${workspaceFolder}",
		chip = probe_chip,
		flashingConfig = { flashingEnabled = true, haltAfterReset = true },
		coreConfigs = probe_cores,
	},
	{
		name = "MP157: Attach gdbserver (USB)",
		type = "gdb",
		request = "attach",
		program = program,
		target = address("192.168.7.1:2345"),
		cwd = "${workspaceFolder}",
	},
}

local configurations = {
	c = native_configs,
	rust = {
		{
			name = "Rust: Launch executable",
			type = "codelldb",
			request = "launch",
			program = program,
			cwd = "${workspaceFolder}",
			stopOnEntry = false,
		},
		{
			name = "Rust: Attach process",
			type = "codelldb",
			request = "attach",
			pid = pick_process,
			cwd = "${workspaceFolder}",
		},
	},
	python = {
		{
			name = "Python: Launch file",
			type = "python",
			request = "launch",
			program = "${file}",
			cwd = "${workspaceFolder}",
			pythonPath = function()
				return M.python_path()
			end,
			console = "integratedTerminal",
			justMyCode = true,
		},
		{
			name = "Python: Attach debugpy",
			type = "python",
			request = "attach",
			connect = { host = "127.0.0.1", port = port(5678) },
			justMyCode = true,
		},
	},
	lua = {
		{ name = "Lua: Launch Neovim script", type = "nlua", request = "attach", program = "${file}" },
		{ name = "Lua: Attach Neovim", type = "nlua", request = "attach", host = "127.0.0.1", port = port(8086) },
	},
}

-- Public state: the statusline reads `M.state` and refreshes on the
-- MayonDebugState User event (or subscribes via on_change) instead of probing
-- package.loaded for whether this module was loaded.
function M.on_change(callback)
	if type(callback) == "function" then
		state_listeners[#state_listeners + 1] = callback
	end
end

local function set_state(value)
	if M.state == value then
		return
	end
	M.state = value
	for _, cb in ipairs(state_listeners) do
		pcall(cb, value)
	end
	vim.api.nvim_exec_autocmds("User", { pattern = "MayonDebugState", data = { state = value } })
	vim.cmd.redrawstatus()
end

function M.setup()
	if M.configured then
		return
	end
	M.configured = true
	local dap = require("dap")
	for name, adapter in pairs(adapters) do
		dap.adapters[name] = adapter
	end
	dap.configurations.c = configurations.c
	dap.configurations.cpp = vim.deepcopy(configurations.c)
	dap.configurations.rust = configurations.rust
	dap.configurations.python = configurations.python
	dap.configurations.lua = configurations.lua
	require("mayon.ui.debug").setup()
	vim.api.nvim_create_user_command("DebugLuaListen", M.listen, { desc = "Listen for Lua debugger" })
	dap.listeners.after.event_initialized.mayon = function()
		set_state("Running")
	end
	dap.listeners.after.event_stopped.mayon = function()
		set_state("Stopped")
	end
	dap.listeners.after.event_continued.mayon = function()
		set_state("Running")
	end
	-- probe-rs reports flashing progress and probe errors through a custom event.
	dap.listeners.before["event_probe-rs-show-message"].mayon = function(_, body)
		local levels = { error = vim.log.levels.ERROR, warning = vim.log.levels.WARN }
		vim.notify(body.message, levels[body.severity] or vim.log.levels.INFO, { title = "probe-rs" })
	end
	dap.listeners.after.configurationDone.mayon_lua = function(session)
		local job = session.config._mayon_lua_job
		if job then
			vim.fn.rpcnotify(job, "nvim_exec_lua", "dofile(...)", { session.config.program })
		end
	end
	dap.listeners.on_session.mayon = function(_, session)
		if session then
			local job = session.config._mayon_lua_job
			if job then
				-- Also runs on adapter EOF, initialize/connect failure and normal exit.
				session.on_close.mayon_lua = function()
					vim.schedule(function()
						stop_lua_job(job)
					end)
				end
			end
		else
			set_state("")
		end
	end
	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			for job in pairs(lua_jobs) do
				stop_lua_job(job)
			end
		end,
	})
	require("mayon.features.java_debug").setup_dap()
end

function M.ensure()
	require("lz.n").trigger_load("nvim-dap")
	M.setup()
	return require("dap")
end
function M.select()
	local dap = M.ensure()
	-- The native selector resolves asynchronous providers (notably jdtls) and
	-- project launch.json configurations before presenting its choices.
	dap.continue({ new = true })
end
function M.breakpoint(kind)
	local dap = M.ensure()
	vim.ui.input({ prompt = kind == "log" and "Log message: " or "Breakpoint condition: " }, function(value)
		if value and value ~= "" then
			if kind == "log" then
				dap.set_breakpoint(nil, nil, value)
			else
				dap.set_breakpoint(value)
			end
		end
	end)
end
function M.listen()
	require("mayon.config.loader").pack("one-small-step-for-vimkind")
	return require("osv").launch({ host = "127.0.0.1", port = 8086, output = true })
end
return M
