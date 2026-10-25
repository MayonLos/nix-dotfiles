local M = { state = "" }
local tools = require("mayon.generated").tools
local lua_jobs = {}

local function stop_lua_job(job)
	if job and lua_jobs[job] then
		pcall(vim.fn.jobstop, job)
		lua_jobs[job] = nil
	end
end

local function input(prompt, default, transform, completion)
	return coroutine.create(function(co)
		vim.ui.input({ prompt = prompt, default = default, completion = completion }, function(value)
			local result = value and value ~= "" and (transform and transform(value) or value) or require("dap").ABORT
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
		return vim.fn.filereadable(path) == 1 and vim.fs.normalize(path) or require("dap").ABORT
	end, "file")
end
local function port(default)
	return function()
		return input("Debug port: ", tostring(default), function(value)
			local number = tonumber(value)
			return number and number % 1 == 0 and number > 0 and number < 65536 and number or require("dap").ABORT
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
			return host and tonumber(p) > 0 and tonumber(p) < 65536 and value or require("dap").ABORT
		end)
	end
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

function M.setup()
	if M.configured then
		return
	end
	M.configured = true
	local dap = require("dap")
	dap.adapters.gdb = { type = "executable", command = tools.gdb, args = { "--interpreter=dap", "--quiet", "--nx" } }
	dap.adapters.codelldb =
		{ type = "server", port = "${port}", executable = { command = tools.codelldb, args = { "--port", "${port}" } } }
	dap.adapters.python = function(callback, config)
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
	end
	dap.adapters.nlua = lua_adapter
	local native = {
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
			pid = require("dap.utils").pick_process,
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
			name = "MP157: Attach gdbserver (USB)",
			type = "gdb",
			request = "attach",
			program = program,
			target = address("192.168.7.1:2345"),
			cwd = "${workspaceFolder}",
		},
	}
	dap.configurations.c = native
	dap.configurations.cpp = vim.deepcopy(native)
	dap.configurations.rust = {
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
			pid = require("dap.utils").pick_process,
			cwd = "${workspaceFolder}",
		},
	}
	dap.configurations.python = {
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
	}
	dap.configurations.lua = {
		{ name = "Lua: Launch Neovim script", type = "nlua", request = "attach", program = "${file}" },
		{ name = "Lua: Attach Neovim", type = "nlua", request = "attach", host = "127.0.0.1", port = port(8086) },
	}
	require("mayon.ui.debug").setup()
	vim.api.nvim_create_user_command("DebugLuaListen", M.listen, { desc = "Listen for Lua debugger" })
	local function state(value)
		M.state = value
		vim.cmd.redrawstatus()
	end
	dap.listeners.after.event_initialized.mayon = function()
		state("Running")
	end
	dap.listeners.after.event_stopped.mayon = function()
		state("Stopped")
	end
	dap.listeners.after.event_continued.mayon = function()
		state("Running")
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
			state("")
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
