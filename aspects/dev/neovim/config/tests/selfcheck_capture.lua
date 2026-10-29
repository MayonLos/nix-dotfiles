-- Load with --cmd before VIMINIT. This observer preserves every original sink.
-- Each process writes its own JSON report and LSP log into isolated XDG dirs.
local M = { events = {}, phase = "startup" }
local initial_log = vim.lsp.log.get_filename()
M.lsp_start = vim.fn.filereadable(initial_log) == 1 and #vim.fn.readfile(initial_log) or 0
M.lsp_seen = M.lsp_start
M.lsp_observations = {}
_G.MayonSelfcheck = M
local function record(source, message, level)
	if (level or 0) >= vim.log.levels.WARN then
		M.events[#M.events + 1] = { source = source, message = tostring(message), level = level, phase = M.phase }
	end
end
M.record = record
-- Observe the logger before serialization: stderr may be split anywhere across
-- libuv chunks. Reassemble server lines instead of guessing from log fragments.
M.stderr_streams = {}
function M.observe_stderr(server, line, stream)
	if line == "" then
		return
	end
	local known = server:find("clangd", 1, true)
		or server:find("nixd", 1, true)
		or server:find("marksman", 1, true)
		or server:find("ruff", 1, true)
		or server:find("cmake-language-server", 1, true)
	local info = line:match("^I%[")
		or line:match("^%[%d%d:%d%d:%d%d INF%]")
		or (server:find("ruff", 1, true) and line:match("^%d%d%d%d%-%d%d%-%d%d .- INFO "))
		or (server:find("cmake-language-server", 1, true) and line:match("^INFO:root:"))
	local warning = line:match("^W%[")
		or line:match("^%[%d%d:%d%d:%d%d WRN%]")
		or (server:find("ruff", 1, true) and line:match("^%d%d%d%d%-%d%d%-%d%d .- WARN "))
	local probe = server:find("nixd", 1, true) and line:match("^E%[[^%]]+%] %d+: hover/idiom/selector: not an idiom$")
	-- clangd's command trace contains cwd/argv continuation lines.
	local continuation = stream.previous_info
		and server:find("clangd", 1, true)
		and (line:match("^%[/.*%]$") or line:match("^/nix/store/"))
	local text = line:gsub("error: Task was cancelled", "")
	local fatal = text:lower():find("error:", 1, true)
		or text:lower():find("panicked at", 1, true)
		or text:find("ERROR", 1, true)
		or text:find("Traceback", 1, true)
		or text:find("Exception", 1, true)
	local level, reason = vim.log.levels.ERROR, nil
	if known and not fatal and (info or warning or continuation or probe) then
		level = (warning or probe) and vim.log.levels.WARN or vim.log.levels.INFO
		reason = probe and "nixd optional selector hover probe; RPC succeeded"
			or "known server log format; rpc transport labels all stderr ERROR"
	end
	stream.previous_info = (info or continuation) and level == vim.log.levels.INFO
	M.lsp_observations[#M.lsp_observations + 1] = { server = server, text = line, level = level, reason = reason }
	record("lsp.log", server .. ": " .. line, level)
end
for _, name in ipairs({ "error", "warn" }) do
	local sink = vim.lsp.log[name]
	vim.lsp.log[name] = function(...)
		local args = { ... }
		if #args > 0 then
			if args[1] == "rpc" and args[3] == "stderr" and type(args[4]) == "string" then
				local server = tostring(args[2])
				local stream = M.stderr_streams[server] or { pending = "" }
				M.stderr_streams[server] = stream
				stream.pending = stream.pending .. args[4]
				while stream.pending:find("\n", 1, true) do
					local stop = stream.pending:find("\n", 1, true)
					local line = stream.pending:sub(1, stop - 1)
					stream.pending = stream.pending:sub(stop + 1)
					M.observe_stderr(server, line, stream)
				end
			else
				record("lsp.log", vim.inspect(args), name == "error" and vim.log.levels.ERROR or vim.log.levels.WARN)
			end
		end
		return sink(...)
	end
end

local wrapped
function M.hook_notify()
	if vim.notify == wrapped then
		return
	end
	local sink = vim.notify
	wrapped = function(message, level, opts)
		record("notify", message, level)
		return sink(message, level, opts)
	end
	vim.notify = wrapped
end
M.hook_notify()
-- Snacks installs its notify sink during VIMINIT and replaces vim.notify on
-- first use. Observe that sink when it is required, before its first call.
local require_module = require
_G.require = function(name)
	local module = require_module(name)
	if name == "snacks.notifier" and not M.notifier_hooked then
		M.notifier_hooked = true
		local sink = module.notify
		module.notify = function(message, level, opts)
			record("snacks.notifier", message, level)
			return sink(message, level, opts)
		end
	end
	return module
end
local function serializable(value, seen)
	if type(value) == "function" or type(value) == "userdata" or type(value) == "thread" then
		return tostring(value)
	end
	if type(value) ~= "table" then
		return value
	end
	seen = seen or {}
	if seen[value] then
		return "<cycle>"
	end
	seen[value] = true
	local result = {}
	local list = vim.islist(value)
	for key, item in pairs(value) do
		result[list and key or tostring(key)] = serializable(item, seen)
	end
	seen[value] = nil
	return result
end
local echo = vim.api.nvim_echo
vim.api.nvim_echo = function(chunks, history, opts)
	for _, chunk in ipairs(chunks) do
		if (opts and opts.err) or chunk[2] == "ErrorMsg" or chunk[2] == "WarningMsg" then
			record("echo", chunk[1], chunk[2] == "WarningMsg" and vim.log.levels.WARN or vim.log.levels.ERROR)
		end
	end
	return echo(chunks, history, opts)
end
local function observed(callback)
	return function(...)
		local args = { ... }
		local ok, result = xpcall(function()
			return callback(unpack(args))
		end, debug.traceback)
		if not ok then
			record("lua_callback", result, vim.log.levels.ERROR)
			error(result, 0)
		end
		return result
	end
end
local schedule = vim.schedule
vim.schedule = function(callback)
	return schedule(observed(callback))
end
local autocmd = vim.api.nvim_create_autocmd
vim.api.nvim_create_autocmd = function(events, opts)
	if type(opts.callback) == "function" then
		opts = vim.tbl_extend("force", opts, { callback = observed(opts.callback) })
	end
	return autocmd(events, opts)
end
vim.api.nvim_create_autocmd({ "VimEnter", "UIEnter", "FileType" }, { callback = M.hook_notify })
function M.finish(final)
	if vim.v.errmsg ~= "" then
		record("v:errmsg", vim.v.errmsg, vim.log.levels.ERROR)
	end
	M.messages = vim.api.nvim_exec2("messages", { output = true }).output
	for line in M.messages:gmatch("[^\n]+") do
		if line:match("E%d+:") or line:match("Error executing") or line:match("stack traceback:") then
			record("messages", line, vim.log.levels.ERROR)
		end
	end
	M.lsp_log = vim.lsp.log.get_filename()
	local lsp_lines = vim.fn.filereadable(M.lsp_log) == 1 and vim.fn.readfile(M.lsp_log) or {}
	for server, stream in pairs(M.stderr_streams) do
		if final == true and stream.pending ~= "" and stream.observed ~= stream.pending then
			M.observe_stderr(server, stream.pending, stream)
			stream.observed = stream.pending
		end
	end
	lsp_lines = vim.list_slice(lsp_lines, M.lsp_start + 1)

	M.errmsg = vim.v.errmsg
	M.load_error = vim.g.mayon_load_error
	if M.load_error then
		record("loader", M.load_error, vim.log.levels.ERROR)
	end
	local path = vim.env.NVIM_SELFCHECK_REPORT or (vim.fn.stdpath("state") .. "/selfcheck.json")
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	vim.fn.writefile({
		vim.json.encode(serializable({
			events = M.events,
			messages = M.messages,
			lsp_log = M.lsp_log,
			errmsg = M.errmsg,
			load_error = M.load_error,
			coverage = M.coverage,
			lsp = lsp_lines,
			lsp_observations = M.lsp_observations,
		})),
	}, path)
	return vim.tbl_filter(function(event)
		return event.level >= vim.log.levels.ERROR
	end, M.events)
end
vim.api.nvim_create_autocmd("VimLeavePre", {
	callback = function()
		M.finish(true)
	end,
})
