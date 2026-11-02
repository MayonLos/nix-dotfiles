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

local function database_uses_cross_compiler(root)
	if not root then
		return false
	end
	local candidates = { root .. "/compile_commands.json", root .. "/build/compile_commands.json" }
	vim.list_extend(candidates, vim.fn.glob(root .. "/cmake-build-*/compile_commands.json", true, true))
	vim.list_extend(candidates, vim.fn.glob(root .. "/build-*/compile_commands.json", true, true))
	for _, path in ipairs(candidates) do
		local file = io.open(path, "r")
		if file then
			local head = file:read(65536) or ""
			file:close()
			if head:find("arm%-none%-eabi%-") or head:find("arm%-ostl%-linux") then
				return true
			end
		end
	end
	return false
end

-- The nixpkgs clangd wrapper stops injecting the host C++ and libc headers once
-- it sees --query-driver, so that flag must only reach cross-compiled projects.
function M.clangd_command(base, root, options)
	local command = vim.deepcopy(base)
	local cross = (options and options.is_cross or database_uses_cross_compiler)(root)
	if cross then
		vim.list_extend(command, M.query_driver_args(options))
	end
	return command
end

function M.configure_clangd(config, options)
	local base = vim.deepcopy(config.cmd or { "clangd" })
	config.base_cmd = base
	config.cmd = function(dispatchers, resolved)
		return vim.lsp.rpc.start(M.clangd_command(base, resolved.root_dir, options), dispatchers, {
			cwd = resolved.cmd_cwd,
			env = resolved.cmd_env,
			detached = resolved.detached,
		})
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

return M
