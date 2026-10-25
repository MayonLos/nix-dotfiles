local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fs.dirname(vim.fs.dirname(source))
vim.opt.rtp:prepend(root)

local embedded = require("mayon.features.embedded")
local sdk_root = vim.fn.tempname() .. "/mp157-sdk"
vim.fn.mkdir(sdk_root .. "/sysroots", "p")
local drivers = embedded.query_driver_args({
	sdk_root = sdk_root,
	is_directory = function(path)
		return path == sdk_root .. "/sysroots"
	end,
	executable_path = function(name)
		return name == "arm-none-eabi-gcc" and "/nix/store/test-toolchain/bin/arm-none-eabi-gcc"
			or name == "arm-none-eabi-g++" and "/nix/store/test-toolchain/bin/arm-none-eabi-g++"
	end,
	realpath = function(path)
		return path:gsub("test%-toolchain", "real-toolchain")
	end,
	is_executable = function()
		return true
	end,
})
assert(#drivers == 1 and drivers[1]:match("^%-%-query%-driver="), "expected one clangd query-driver argument")
assert(
	drivers[1]:find(sdk_root .. "/sysroots/*/usr/bin/arm-ostl-linux*/arm-ostl-linux*-gcc", 1, true),
	"MP157 SDK cross compiler glob is missing"
)
assert(
	drivers[1]:find("/nix/store/test-toolchain/bin/arm-none-eabi-gcc", 1, true),
	"STM32 compiler must be trusted by path"
)
assert(
	drivers[1]:find("/nix/store/real-toolchain/bin/arm-none-eabi-gcc", 1, true),
	"STM32 resolved compiler path should remain trusted alongside its profile alias"
)
assert(drivers[1]:find("arm-none-eabi-g++", 1, true), "STM32 C++ compiler must be trusted by path")

local no_sdk = embedded.query_driver_args({
	sdk_root = sdk_root .. "/absent",
	is_directory = function()
		return false
	end,
	executable_path = function()
		return nil
	end,
})
assert(#no_sdk == 0, "missing SDKs must not add broad clangd compiler permissions")

local clangd = embedded.configure_clangd({ cmd = { "clangd", "--background-index" } }, {
	sdk_root = sdk_root,
	is_directory = function(path)
		return path == sdk_root .. "/sysroots"
	end,
	executable_path = function()
		return nil
	end,
})
assert(clangd.cmd[1] == "clangd" and clangd.cmd[2] == "--background-index")
assert(clangd.cmd[3]:match("^%-%-query%-driver="), "clangd command should receive the SDK-only driver allowlist")

local input = vim.ui.input
local executable = vim.fn.executable
local fs_stat = vim.uv.fs_stat
local jobstart = vim.fn.jobstart
local launched
vim.fn.executable = function(name)
	return name == "tio" and 1 or executable(name)
end
vim.uv.fs_stat = function(path)
	if path == "/dev/serial/by-id/usb-fixture" or path == "/dev/ttyUSB-fixture" then
		return { type = "char" }
	end
	return fs_stat(path)
end
vim.fn.jobstart = function(argv, options)
	launched = { argv = argv, options = options }
	return 42
end

vim.ui.input = function(_, callback)
	callback(nil)
end
assert(embedded.serial(), "available tio should expose the explicit serial prompt")
assert(launched == nil, "canceling the device prompt must not open a serial device")

local prompts = { "/dev/serial/by-id/usb-fixture", "921600" }
vim.ui.input = function(_, callback)
	callback(table.remove(prompts, 1))
end
assert(embedded.serial(), "serial prompt should accept an explicit device and baud rate")
assert(
	vim.deep_equal(launched.argv, { "tio", "--baudrate", "921600", "/dev/serial/by-id/usb-fixture" })
		and launched.options.term == true,
	"serial must start tio with argv and the explicitly selected device"
)
local first_serial_buf = vim.api.nvim_get_current_buf()
prompts = { "/dev/serial/by-id/usb-fixture", "115200" }
assert(embedded.serial(), "reopening the same serial device must not collide with an existing buffer name")
assert(vim.api.nvim_get_current_buf() ~= first_serial_buf, "each serial launch should own its terminal buffer")

launched = nil
prompts = { "/dev/ttyUSB-fixture", "0; touch /tmp/not-a-command" }
vim.ui.input = function(_, callback)
	callback(table.remove(prompts, 1))
end
embedded.serial()
assert(launched == nil, "invalid baud input must not start tio or reach a shell")

vim.ui.input = input
vim.fn.executable = executable
vim.uv.fs_stat = fs_stat
vim.fn.jobstart = jobstart
vim.fn.delete(sdk_root, "rf")
print("Embedded clangd and explicit serial fixtures passed")
