-- Adapter paths and the entire debugger stay inert until an explicit action.
assert(not package.loaded.dap and not package.loaded["dap-view"] and not package.loaded.osv)
assert(not package.loaded["mayon.features.debug"], "debug feature loaded during startup")
local tools = require("mayon.generated").tools
for _, name in ipairs({ "gdb", "codelldb", "debugpy_python", "jdtls", "java" }) do
	assert(
		tools[name]:match("^/nix/store/") and vim.fn.executable(tools[name]) == 1,
		"adapter is not Nix-owned: " .. name
	)
end
local bundles = dofile(tools.java_debug_manifest)
assert(#bundles > 1)
for _, jar in ipairs(bundles) do
	assert(vim.fn.filereadable(jar) == 1)
end
local debug = require("mayon.features.debug")
local dap = debug.ensure()
assert(package.loaded["dap-view"] and package.loaded["nvim-dap-virtual-text"])
assert(not package.loaded.osv, "OSV should load only in a Lua target or explicit listener")
for _, ft in ipairs({ "c", "cpp", "python", "rust", "lua" }) do
	assert(#dap.configurations[ft] >= 2, "missing launch/attach configurations for " .. ft)
	for _, config in ipairs(dap.configurations[ft]) do
		assert(dap.adapters[config.type], "unregistered adapter")
	end
end
assert(dap.adapters.gdb.command == tools.gdb)
assert(dap.adapters.codelldb.executable.command == tools.codelldb)
assert(dap.configurations.c[3].name:match("STM32") and dap.configurations.c[4].name:match("MP157"))

-- A failed owned Neovim must not survive initialization or adapter EOF. An
-- externally attached editor is never ours to stop.
local start, request, stop = vim.fn.jobstart, vim.fn.rpcrequest, vim.fn.jobstop
local stopped = {}
vim.fn.jobstart = function()
	return 987654
end
vim.fn.jobstop = function(job)
	stopped[#stopped + 1] = job
end
vim.fn.rpcrequest = function()
	error("fixture initialization failure")
end
assert(not pcall(dap.adapters.nlua, function()
	error("unexpected adapter callback")
end, { program = "fixture.lua" }))
assert(vim.deep_equal(stopped, { 987654 }), "failed Lua target leaked")
vim.fn.rpcrequest = function()
	return nil
end
assert(not pcall(dap.adapters.nlua, function()
	error("unexpected adapter callback")
end, { program = "fixture.lua" }))
assert(#stopped == 2, "nil OSV listener leaked its target")
vim.fn.rpcrequest = function()
	return { port = 45678 }
end
local owned = { config = { program = "fixture.lua" }, on_close = {} }
dap.adapters.nlua(function(adapter)
	assert(adapter.port == 45678)
end, owned.config)
dap.listeners.on_session.mayon(nil, owned)
assert(owned.on_close.mayon_lua)
owned.on_close.mayon_lua()
assert(
	vim.wait(1000, function()
		return #stopped == 3
	end),
	"closed Lua target leaked"
)
local external = { config = { host = "127.0.0.1", port = 8086 }, on_close = {} }
dap.adapters.nlua(function(adapter)
	assert(adapter.port == 8086)
end, external.config)
dap.listeners.on_session.mayon(nil, external)
assert(external.on_close.mayon_lua == nil, "external Lua editor must not be stopped")
vim.fn.jobstart, vim.fn.rpcrequest, vim.fn.jobstop = start, request, stop
local continue = dap.continue
local selected
dap.continue = function(opts)
	selected = opts
end
debug.select()
dap.continue = continue
assert(selected and selected.new, "configuration selector must resolve native async providers")

local original_input, original_schedule = vim.ui.input, vim.schedule
local reply
vim.ui.input = function(_, callback)
	callback(reply)
end
vim.schedule = function(callback)
	callback()
end
local function resolve(prompt, value)
	reply = value
	local result
	local co = coroutine.create(function()
		result = coroutine.yield()
	end)
	assert(coroutine.resume(co))
	assert(coroutine.resume(prompt(), co))
	return result
end
local remote = dap.configurations.c[3]
assert(resolve(remote.target, nil) == dap.ABORT)
assert(resolve(remote.target, "localhost:0") == dap.ABORT)
assert(resolve(remote.target, "localhost:65536") == dap.ABORT)
assert(resolve(remote.target, "[::1]:3333") == "[::1]:3333")
assert(resolve(remote.target, "127.0.0.1:3333") == "127.0.0.1:3333")
assert(resolve(remote.program, nil) == dap.ABORT)
assert(resolve(remote.program, "/absent/r28b/firmware.elf") == dap.ABORT)
vim.ui.input, vim.schedule = original_input, original_schedule
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp .. "/.venv/bin", "p")
vim.fn.writefile({ "#!/bin/sh", "exit 0" }, tmp .. "/.venv/bin/python")
vim.fn.setfperm(tmp .. "/.venv/bin/python", "rwx------")
assert(debug.python_path(tmp) == tmp .. "/.venv/bin/python", "project venv must have priority")
vim.fn.delete(tmp, "rf")
local config = require("dap-view.setup").config
assert(config.auto_toggle == true and config.windows.position == "below" and config.windows.size == 12)
assert(not config.winbar.controls.enabled, "no debugging toolbar")
assert(
	vim.deep_equal(
		config.winbar.sections,
		{ "scopes", "watches", "breakpoints", "stack", "threads", "repl", "console" }
	)
)
assert(config.help.border == "single")
local view = require("dap-view")
view.open()
local state = require("dap-view.state")
assert(state.winnr and vim.api.nvim_win_is_valid(state.winnr))
assert(vim.api.nvim_win_get_height(state.winnr) == 12)
view.show_view("stack")
assert(vim.bo[vim.api.nvim_win_get_buf(state.winnr)].filetype == "dap-view")
local get_session, up, focus = dap.session, dap.up, dap.focus_frame
local stack_frames = {
	{ id = 1, name = "callee", source = { path = "fixture.c" }, line = 4 },
	{ id = 2, name = "caller", source = { path = "fixture.c" }, line = 10 },
}
local stack_session =
	{ stopped_thread_id = 1, threads = { [1] = { frames = stack_frames } }, current_frame = stack_frames[1] }
dap.session = function()
	return stack_session
end
dap.up = function()
	stack_session.current_frame = stack_frames[2]
	dap.listeners.after.scopes.mayon_stack()
end
dap.focus_frame = function() end
config.winbar.custom_sections.stack.action()
local stack_buf = vim.api.nvim_win_get_buf(state.winnr)
vim.api.nvim_set_current_win(state.winnr)
vim.api.nvim_win_set_cursor(state.winnr, { 2, 0 })
vim.fn.maparg("<CR>", "n", false, true).callback()
assert(
	vim.wait(1000, function()
		return vim.api.nvim_buf_get_lines(stack_buf, 1, 2, false)[1]:match("^▸ caller")
	end),
	"selected stack frame marker did not refresh after scopes"
)
assert(not vim.wo[state.winnr].number and not vim.wo[state.winnr].relativenumber)
dap.session, dap.up, dap.focus_frame = get_session, up, focus
view.close(true)
assert(not state.winnr or not vim.api.nvim_win_is_valid(state.winnr))
for _, name in ipairs({ "DapBreakpoint", "DapBreakpointCondition", "DapLogPoint", "DapStopped" }) do
	local sign = vim.fn.sign_getdefined(name)[1]
	assert(sign and sign.texthl == name)
end
assert(vim.api.nvim_get_hl(0, { name = "DapStoppedLine" }).underline)
assert(not vim.api.nvim_get_hl(0, { name = "DapStoppedLine" }).bg)
assert(vim.api.nvim_get_hl(0, { name = "NvimDapViewTabSelected" }).underline)
for _, lhs in ipairs({
	"<F5>",
	"<F9>",
	"<F10>",
	"<F11>",
	"<S-F11>",
	"<leader>dC",
	"<leader>dR",
	"<leader>dt",
	"<leader>dB",
	"<leader>dL",
	"<leader>dX",
	"<leader>de",
	"<leader>du",
	"<leader>ds",
	"<leader>dl",
}) do
	assert(vim.fn.maparg(lhs, "n", false, true).desc, "missing debugger binding: " .. lhs)
end
-- The pinned Java ftplugin must not leave its silent E216 behind on cleanup.
local b = vim.api.nvim_create_buf(false, true)
vim.bo[b].filetype = "java"
vim.bo[b].filetype = "text"
assert(vim.v.errmsg == "", vim.v.errmsg)
vim.api.nvim_buf_delete(b, { force = true })
print("Lazy Nix adapters, venv, debug panel, signs, keys and Java cleanup passed")
