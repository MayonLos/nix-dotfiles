local M = {}

local function default_query_driver_options()
	local home = vim.env.HOME or vim.fn.expand("~")
	local sdk_root = vim.fs.normalize(home .. "/.local/share/mp157-sdk")
	return {
		sdk_root = sdk_root,
		is_directory = function(path)
			return vim.fn.isdirectory(path) == 1
		end,
		executable_path = function(name)
			local path = vim.fn.exepath(name)
			return path ~= "" and path or nil
		end,
		realpath = function(path)
			return vim.uv.fs_realpath(path)
		end,
		is_executable = function(path)
			return vim.fn.executable(path) == 1
		end,
	}
end

function M.query_driver_args(options)
	local opts = vim.tbl_extend("force", default_query_driver_options(), options or {})
	local drivers = {}
	if opts.sdk_root and opts.is_directory(opts.sdk_root .. "/sysroots") then
		-- Keep clangd's compiler execution permission inside the vendor SDK.
		-- The driver prints target-specific built-in headers and sysroot data;
		-- project compile_commands still decides the target and actual sysroot.
		drivers[#drivers + 1] = opts.sdk_root .. "/sysroots/*/usr/bin/arm-ostl-linux*/arm-ostl-linux*-gcc"
		drivers[#drivers + 1] = opts.sdk_root .. "/sysroots/*/usr/bin/arm-ostl-linux*/arm-ostl-linux*-g++"
	end
	for _, name in ipairs({ "arm-none-eabi-gcc", "arm-none-eabi-g++" }) do
		local path = opts.executable_path(name)
		if type(path) == "string" and path ~= "" and opts.is_executable(path) then
			drivers[#drivers + 1] = path
			local realpath = opts.realpath(path)
			if realpath and realpath ~= path and opts.is_executable(realpath) then
				drivers[#drivers + 1] = realpath
			end
		end
	end
	if #drivers == 0 then
		return {}
	end
	return { "--query-driver=" .. table.concat(drivers, ",") }
end

function M.configure_clangd(config, options)
	config.cmd = vim.deepcopy(config.cmd or { "clangd" })
	local args = M.query_driver_args(options)
	for _, arg in ipairs(args) do
		local exists = false
		for _, current in ipairs(config.cmd) do
			if current:match("^%-%-query%-driver=") then
				exists = true
				break
			end
		end
		if not exists then
			config.cmd[#config.cmd + 1] = arg
		end
	end
	return config
end

local function serial_device_allowed(path)
	if
		type(path) ~= "string"
		or not (path:match("^/dev/tty[%w_%-]+$") or path:match("^/dev/serial/by%-id/[%w_.+%-]+$"))
	then
		return false
	end
	local stat = vim.uv.fs_stat(path)
	return stat ~= nil and stat.type == "char"
end

local function open_serial(device, baud)
	vim.cmd("botright 12new")
	local buffer = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_name(buffer, ("Serial %s [%d]"):format(device, buffer))
	vim.bo[buffer].bufhidden = "hide"
	local ok, job = pcall(vim.fn.jobstart, { "tio", "--baudrate", baud, device }, { term = true })
	if not ok or type(job) ~= "number" or job <= 0 then
		vim.notify("无法启动 tio 串口终端", vim.log.levels.ERROR, { title = "串口" })
		return false
	end
	if #vim.api.nvim_list_uis() > 0 then
		vim.cmd.startinsert()
	end
	return true
end

function M.serial()
	if vim.fn.executable("tio") ~= 1 then
		vim.notify("未找到 tio；请先启用 embedded-workbench", vim.log.levels.WARN, { title = "串口" })
		return false
	end
	vim.ui.input({ prompt = "串口设备路径（如 /dev/ttyUSB0）: " }, function(device)
		if not device or device == "" then
			return
		end
		if not serial_device_allowed(device) then
			vim.notify("请输入存在的 /dev/tty* 或 /dev/serial/by-id/* 字符设备", vim.log.levels.WARN, {
				title = "串口",
			})
			return
		end
		vim.ui.input({ prompt = "波特率: ", default = "115200" }, function(baud)
			if not baud or baud == "" then
				return
			end
			local numeric = tonumber(baud)
			if not baud:match("^%d+$") or not numeric or numeric < 50 or numeric > 4000000 then
				vim.notify("波特率应为 50 到 4000000 之间的整数", vim.log.levels.WARN, { title = "串口" })
				return
			end
			open_serial(device, baud)
		end)
	end)
	return true
end

local function remote_target(target, options)
	local opts = options or {}
	local host, port = target:match("^([^:]+):(%d+)$")
	local ipv6_host, ipv6_port = target:match("^(%[[%x:]+%]):(%d+)$")
	host, port = host or ipv6_host, port or ipv6_port
	if not host or not tonumber(port) or tonumber(port) < 1 or tonumber(port) > 65535 then
		return opts.abort or require("dap").ABORT
	end
	return host .. ":" .. port
end

local function dap_input(prompt, default, completion, transform, options)
	local opts = options or {}
	return coroutine.create(function(dap_run_co)
		vim.ui.input({
			prompt = prompt,
			default = default,
			completion = completion,
			title = opts.title,
		}, function(value)
			local result = value and value ~= "" and transform(value) or (opts.abort or require("dap").ABORT)
			vim.schedule(function()
				if coroutine.status(dap_run_co) == "suspended" then
					coroutine.resume(dap_run_co, result)
				end
			end)
		end)
	end)
end

function M.dap_configuration(options)
	local opts = options or {}
	local program = function()
		return dap_input("Firmware ELF: ", vim.fn.getcwd() .. "/", "file", function(path)
			return path
		end, { abort = opts.abort, title = "GDB symbols · ELF" })
	end
	local config = {
		name = "GDB remote (host GDB)",
		type = "gdb",
		request = "attach",
		program = program,
		target = opts.target or function()
			return dap_input("GDB remote target (host:port): ", "localhost:3333", nil, function(target)
				return remote_target(target, opts)
			end, { abort = opts.abort, title = "GDB remote · target" })
		end,
		cwd = "${workspaceFolder}",
	}
	return {
		adapter = {
			type = "executable",
			command = opts.gdb or "gdb",
			args = { "--interpreter=dap", "--eval-command", "set print pretty on" },
		},
		configurations = { c = { vim.deepcopy(config) }, cpp = { vim.deepcopy(config) } },
	}
end

function M.setup_dap(dap)
	local gdb = vim.fn.exepath("gdb")
	if gdb == "" then
		vim.notify("未找到支持 DAP 的 host gdb", vim.log.levels.WARN, { title = "DAP" })
		return false
	end
	dap = dap or require("dap")
	local setup = M.dap_configuration({ gdb = gdb })
	dap.adapters.gdb = setup.adapter
	for _, filetype in ipairs({ "c", "cpp" }) do
		dap.configurations[filetype] = dap.configurations[filetype] or {}
		vim.list_extend(dap.configurations[filetype], setup.configurations[filetype])
	end
	return true
end

return M
