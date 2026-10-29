-- Offline inventory and safe action sweep for the runtime self-check.
-- Run in a process with isolated HOME/XDG and NVIM_SELFCHECK_ACTIONS_DIR set.
local capture = assert(_G.MayonSelfcheck, "load selfcheck_capture.lua before selfcheck_actions.lua")
local root = vim.env.NVIM_SELFCHECK_ACTIONS_DIR or vim.fn.tempname()
local home = vim.fn.fnamemodify(vim.env.HOME or "", ":p")
local temp = vim.fn.fnamemodify(vim.env.TMPDIR or "/tmp", ":p")
local function inside(path, parent)
	parent = parent:gsub("/$", "")
	return path == parent or path:sub(1, #parent + 1) == parent .. "/"
end
root = vim.fn.fnamemodify(root, ":p"):gsub("/+$", "")
local explicit_synthetic_root = vim.env.NVIM_SELFCHECK_ACTIONS_DIR ~= nil
	and vim.fn.fnamemodify(root:gsub("/+$", ""), ":t") == "actions-state"
assert(
	root ~= "/" and (inside(root, home) or inside(root, temp) or explicit_synthetic_root),
	"actions fixture must be under isolated HOME/TMPDIR or explicitly named actions-state"
)
capture.phase = "actions"
vim.fn.mkdir(root, "p")
local project = root .. "/project"
vim.fn.mkdir(project, "p")
vim.fn.writefile(
	{ "# Offline action fixture", "", "A small local file for picker and document actions." },
	project .. "/README.md"
)
vim.cmd.cd(project)
vim.cmd.edit(vim.fn.fnameescape(project .. "/README.md"))
vim.bo.filetype = "text"
local fixture_item = { filename = project .. "/README.md", lnum = 1, col = 1, text = "offline fixture item" }
vim.fn.setqflist({}, " ", { items = { fixture_item } })
vim.fn.setloclist(0, {}, " ", { items = { fixture_item } })

-- Headless command-line runs may execute test commands before VimEnter. Fire
-- that pending lifecycle event so delayed setup and lazy specs match a real UI.
if vim.v.vim_did_enter ~= 1 then
	vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
end
vim.api.nvim_exec_autocmds("User", { pattern = "MayonVeryLazy", modeline = false })
require("lz.n").trigger_load("which-key.nvim")
require("mayon.ui.whichkey").setup()
vim.wait(50)
local which_key_config_module = require("which-key.config")
if not which_key_config_module.loaded then
	vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
	vim.wait(50)
end

local report = { root = root, modes = {}, mappings = {}, commands = {}, which_key = {}, summary = {} }
local destination = root .. "/actions-inventory.json"
local function flush_report()
	vim.fn.writefile({ vim.json.encode(report) }, destination)
end
local modes = { "n", "i", "v", "x", "s", "o", "c", "t", "l" }
local verified_tests = {}
for test in (vim.env.NVIM_SELFCHECK_VERIFIED_TESTS or ""):gmatch("[^,]+") do
	verified_tests[test] = true
end
report.verified_tests = vim.tbl_keys(verified_tests)
table.sort(report.verified_tests)
local function evidence_for(description)
	local text = (description or ""):lower()
	local candidates = {}
	local function add(name)
		if verified_tests[name] then
			candidates[#candidates + 1] = "aspects/dev/neovim/config/tests/" .. name .. ".lua"
		end
	end
	if text:find("copilot", 1, true) or text:find("completion", 1, true) or text:find("ai", 1, true) then
		add("selfcheck_offline")
		add("completion")
		add("completion_ui")
		add("ai")
	elseif text:find("debug", 1, true) or text:find("breakpoint", 1, true) then
		add("debug")
		add("debug_gdb")
	elseif
		text:find("git", 1, true)
		or text:find("hunk", 1, true)
		or text:find("diff", 1, true)
		or text:find("stage", 1, true)
	then
		add("workflow")
		add("integration")
	elseif text:find("rename", 1, true) or text:find("trash", 1, true) or text:find("file", 1, true) then
		add("fileops")
	elseif text:find("symbol", 1, true) or text:find("lsp", 1, true) or text:find("diagnostic", 1, true) then
		add("runtime_smoke")
	end
	return #candidates > 0 and candidates or nil
end
local function safe_map(map)
	local description = (map.desc or ""):lower()
	local safe_pickers = {
		["pick files"] = true,
		["pick buffers"] = true,
		["pick document symbols"] = true,
		["pick workspace symbols"] = true,
		["pick text search"] = true,
		["pick recent files"] = true,
		["find files"] = true,
		["find files and text"] = true,
		["switch buffers"] = true,
		["find recent files"] = true,
		["find document symbols"] = true,
		["find workspace symbols"] = true,
		["find diagnostics"] = true,
		["find command history"] = true,
		["resume last search"] = true,
		["find keymaps"] = true,
		["find help"] = true,
		["search text"] = true,
		["search and replace"] = true,
		["show notifications"] = true,
		["show undo history"] = true,
		["open file tree"] = true,
		["find projects"] = true,
		["find recent files"] = true,
		["pick code context"] = true,
		["search word under cursor"] = true,
	}
	if safe_pickers[description] then
		return "execute", "offline picker on synthetic project"
	end
	if description == "show keymaps" then
		return "skip", "opens an interactive which-key popup; its setup and resolved tree are inventoried separately"
	end
	if description:find("工具窗口", 1, true) then
		return "stub", "invoke the configured workspace keymap callback with the workspace effect boundary replaced"
	end
	if description == "show editor status" then
		return "execute", "read-only status command"
	end
	local synthetic_actions = {
		["save buffer"] = "writes only the synthetic fixture buffer",
		["format buffer"] = "formats only the synthetic text buffer; subprocess APIs are stubbed",
		["create file"] = "creates an unnamed buffer only; no path is written",
		["open scratch buffer"] = "opens a scratch buffer in the isolated editor",
		["close buffer"] = "closes a disposable synthetic buffer",
		["close other buffers"] = "closes only disposable synthetic buffers",
		["close window or buffer"] = "closes a disposable synthetic split",
	}
	if synthetic_actions[description] then
		return "execute", synthetic_actions[description]
	end
	local safe_toggles = {
		["toggle line wrap"] = true,
		["toggle spell check"] = true,
		["toggle relative numbers"] = true,
		["toggle diagnostics"] = true,
		["toggle symbol outline"] = true,
		["toggle location list"] = true,
		["toggle quickfix list"] = true,
		["toggle inlay hints"] = true,
		["toggle zen mode"] = true,
	}
	if safe_toggles[description] then
		return "execute", "reversible local editor option or outline"
	end
	if
		description == "show code outline"
		or description == "browse directory"
		or description == "clear search highlight"
	then
		return "execute", "local synthetic buffer UI action; no write or external process"
	end
	if not map.desc then
		return "skip", "no user description; likely native or plugin mapping"
	end
	if description == "toggle codex cli" or description == "toggle grok cli" then
		return "skip",
			"Sidekick creates an interactive terminal session whose channel cannot be represented by an offline process stub"
	end
	local unsafe = {
		"save",
		"write",
		"format",
		"rename",
		"delete",
		"trash",
		"terminal",
		"lazygit",
		"git",
		"debug",
		"breakpoint",
		"launch",
		"attach",
		"disconnect",
		"task",
		"serial",
		"code action",
		"lint",
		"link",
		"url",
		"remote",
		"assistant",
		"copilot",
		"deepseek",
		"claude",
		"codecompanion",
		"grok",
		"codex",
		"sidekick",
		"completion",
		"session",
		"quit",
		"build",
		"clean",
		"run",
		"insert",
		"surround",
		"multicursor",
		"macro",
		"stage",
		"reset",
		"hunk",
		"commit",
		"revision",
		"history",
		"conflict",
		"blame",
		"yazi",
		"diff",
	}
	for _, token in ipairs(unsafe) do
		if description:find(token, 1, true) then
			local reason = "requires external process, network, mutation, device, or explicit user data: " .. token
			if
				token == "assistant"
				or token == "copilot"
				or token == "deepseek"
				or token == "claude"
				or token == "codecompanion"
				or token == "grok"
				or token == "codex"
				or token == "sidekick"
			then
				reason = "AI request boundary: no offline response fixture is wired to this mapping; no request sent"
				if token == "completion" and description == "cycle ai completion" then
					return "stub",
						"Copilot is backed by selfcheck_offline.lua; DeepSeek request transport remains blocked"
				end
				if map.callback then
					return "stub",
						"invoke the configured AI UI/prompt callback; no prompt is submitted and external transports are stubbed"
				end
			elseif token == "git" or token == "stage" or token == "reset" or token == "hunk" or token == "commit" then
				reason = "Git context or repository mutation; no Git subprocess or state change allowed"
				if map.callback then
					return "stub",
						"invoke the configured callback with all system/job process APIs replaced by offline stubs"
				end
			elseif token == "link" or token == "url" or token == "remote" then
				return "stub",
					"invoke the configured callback with vim.ui.open and process APIs replaced by offline stubs"
			elseif token == "terminal" or token == "lazygit" or token == "yazi" then
				reason = "would start an external CLI; process launch prohibited"
				if map.callback then
					return "stub",
						"invoke configured terminal callback with terminal/job/system launch replaced by offline stub"
				end
			elseif token == "debug" or token == "breakpoint" or token == "launch" or token == "attach" then
				reason = "requires a target process or listener; none started"
				if map.callback then
					return "stub",
						"invoke configured debug callback with DAP launch/continue/step/disconnect replaced by offline stubs"
				end
			elseif
				token == "diff"
				or token == "revision"
				or token == "history"
				or token == "conflict"
				or token == "blame"
			then
				if map.callback then
					return "stub", "invoke configured Git UI callback with process APIs replaced by offline stubs"
				end
			end
			return "skip", reason
		end
	end
	return "skip", "context-specific action not selected for synthetic text buffer"
end

local function mapping_inventory(mode, maps, scope, buffer)
	local local_rows = {}
	for _, map in ipairs(maps) do
		local disposition, reason = safe_map(map)
		if scope == "buffer" and buffer ~= vim.api.nvim_get_current_buf() and disposition == "execute" then
			disposition = "skip"
			reason =
				"buffer-local action requires that buffer's filetype and tool context; inventoried without switching synthetic state"
		end
		local row = {
			mode = mode,
			scope = scope,
			buffer = buffer,
			lhs = map.lhs,
			desc = map.desc,
			rhs = map.rhs,
			callback = type(map.callback) == "function",
			disposition = disposition,
			reason = reason,
			verified_by = evidence_for(map.desc),
		}
		report.mappings[#report.mappings + 1] = row
		local_rows[#local_rows + 1] = row
	end
	report.modes[scope .. (buffer and (":" .. buffer .. ":" .. vim.bo[buffer].filetype .. ":" .. vim.bo[buffer].buftype) or "") .. ":" .. mode] =
		#local_rows
	return local_rows
end

local map_groups = {}
for _, mode in ipairs(modes) do
	map_groups[#map_groups + 1] = { mode = mode, maps = vim.api.nvim_get_keymap(mode), scope = "global" }
end
for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
	if vim.api.nvim_buf_is_valid(buffer) then
		for _, mode in ipairs(modes) do
			map_groups[#map_groups + 1] = {
				mode = mode,
				maps = vim.api.nvim_buf_get_keymap(buffer, mode),
				scope = "buffer",
				buffer = buffer,
			}
		end
	end
end
for _, group in ipairs(map_groups) do
	mapping_inventory(group.mode, group.maps, group.scope, group.buffer)
end

-- which-key's public spec queue plus its resolved buffer tree expose both
-- declarative groups and concrete mappings without opening a blocking popup.
local wk = require("which-key")
report.which_key_setup = wk.did_setup == true
report.which_key_config_loaded = which_key_config_module.loaded == true
report.which_key_modes = {}
local which_key_config = require("mayon.ui.whichkey").config()
local function add_spec(entries, prefix)
	for _, item in ipairs(entries or {}) do
		if type(item) == "table" then
			local keys = item[1] or item.keys
			if keys then
				report.which_key[#report.which_key + 1] = {
					lhs = prefix and (prefix .. " " .. keys) or keys,
					desc = item.desc,
					group = item.group,
					disposition = "configured_spec",
					reason = "which-key configuration spec",
				}
			end
			add_spec(item, keys or prefix)
		end
	end
end
add_spec(which_key_config.spec)
for _, queued in ipairs(wk._queue or {}) do
	for _, item in ipairs(queued.spec or {}) do
		report.which_key[#report.which_key + 1] = {
			lhs = item[1] or item.keys,
			desc = item.desc,
			group = item.group,
			disposition = "inventory",
			reason = "which-key declarative spec",
		}
	end
end
for _, mode in ipairs({ "n", "i", "v", "x", "s", "o", "c", "t", "l" }) do
	local ok, buffer = pcall(require("which-key.buf").get, { mode = mode, buf = 0 })
	if ok and buffer and buffer.tree and buffer.tree.root then
		local mode_count = 0
		local function visit(node)
			if node.keymap then
				mode_count = mode_count + 1
				report.which_key[#report.which_key + 1] = {
					mode = mode,
					keys = node.keys,
					desc = node.keymap.desc,
					group = node.group,
					disposition = "resolved",
					reason = "resolved which-key tree entry",
				}
			end
			for _, child in pairs(node._children or {}) do
				visit(child)
			end
		end
		visit(buffer.tree.root)
		report.which_key_modes[mode] = mode_count
	elseif not ok then
		report.which_key_modes[mode] = "error: " .. tostring(buffer)
	else
		report.which_key_modes[mode] = 0
	end
end

local function close_picker()
	local picker = require("snacks.picker")
	for _, item in ipairs(picker.get({ tab = true })) do
		item:close()
	end
end

-- Run a deliberately narrow allowlist of callbacks with no shell, network,
-- device, save, or project-state action. The inventory still records every map.
local effective_local = {}
for _, row in ipairs(report.mappings) do
	if row.scope == "buffer" and row.buffer == vim.api.nvim_get_current_buf() then
		effective_local[row.mode .. ":" .. row.lhs] = true
	end
end
-- Seed reversible toggles in their enabled state so their routine notices are
-- informational rather than expected warning noise.
vim.diagnostic.enable(false)
vim.wo.wrap = false
local ran = {}
local effects, action_name, next_job = {}, nil, 91000
local function record_effect(kind, command)
	effects[#effects + 1] = { action = action_name, kind = kind, command = vim.inspect(command) }
	return next_job
end
local function with_offline_boundaries(callback, description)
	local original = {
		system = vim.system,
		jobstart = vim.fn.jobstart,
		termopen = vim.fn.termopen,
		system_fn = vim.fn.system,
		systemlist = vim.fn.systemlist,
		open = vim.ui.open,
		select = vim.ui.select,
		input = vim.ui.input,
		mode = vim.fn.mode,
		execute = os.execute,
		popen = io.popen,
		uv_spawn = vim.uv.spawn,
	}
	local plugin_boundaries = {}
	local function replace(target, name, kind)
		if target and type(target[name]) == "function" then
			plugin_boundaries[#plugin_boundaries + 1] = { target = target, name = name, fn = target[name] }
			target[name] = function(...)
				record_effect(kind or name, { ... })
				return true
			end
		end
	end
	local snacks = require("snacks")
	replace(snacks, "terminal", "Snacks.terminal")
	-- The Snacks public value is a callable module table, so stub its `open`
	-- operation while keeping the configured mapping callback live.
	replace(require("snacks.gitbrowse"), "open", "Snacks.gitbrowse.open")
	for _, name in ipairs({ "Neogit", "CodeDiff", "CodeCompanionChat", "Trouble", "AerialToggle" }) do
		replace(vim.cmd, name, "vim.cmd." .. name)
	end
	local workspace = require("mayon.ui.workspace")
	-- Workspace dispatch is the effect boundary for the keymap's Git, AI,
	-- terminal and project tool-window actions. The keymap callback itself runs.
	replace(workspace, "action", "workspace.action")
	if description:lower():find("codex", 1, true) or description:lower():find("grok", 1, true) then
		require("lz.n").trigger_load("sidekick.nvim")
		replace(require("sidekick.cli"), "toggle", "sidekick.cli.toggle")
	end
	if
		description:lower():find("git", 1, true)
		or description:lower():find("hunk", 1, true)
		or description:lower():find("blame", 1, true)
	then
		require("lz.n").trigger_load("gitsigns.nvim")
		local gitsigns = require("gitsigns")
		for _, name in ipairs({
			"stage_buffer",
			"reset_buffer",
			"stage_hunk",
			"reset_hunk",
			"undo_stage_hunk",
			"toggle_current_line_blame",
			"preview_hunk",
			"next_hunk",
			"prev_hunk",
		}) do
			replace(gitsigns, name, "gitsigns." .. name)
		end
	end
	vim.system = function(command, opts, on_exit)
		next_job = next_job + 1
		local id = record_effect("vim.system", command)
		local result = { code = 0, signal = 0, stdout = "", stderr = "" }
		local argv = type(command) == "table" and table.concat(command, " ") or tostring(command)
		if argv:find("remote %-v") then
			result.stdout = "origin\thttps://example.invalid/offline/repo.git (fetch)\n"
		elseif argv:find("rev%-parse %-%-abbrev%-ref HEAD") then
			result.stdout = "main\n"
		elseif argv:find("ls%-files %-%-full%-name") then
			result.stdout = "README.md\n"
		end
		if on_exit then
			vim.schedule(function()
				on_exit(result)
			end)
		end
		return {
			wait = function()
				return result
			end,
			kill = function()
				return true
			end,
			is_closing = function()
				return false
			end,
			write = function()
				return true
			end,
			close = function()
				return true
			end,
			id = id,
		}
	end
	vim.uv.spawn = function(path, options, on_exit)
		next_job = next_job + 1
		local id = record_effect("vim.uv.spawn", { path = path, options = options })
		local handle = {
			close = function(self, callback)
				if callback then
					callback()
				end
				return true
			end,
			kill = function()
				return true
			end,
			is_closing = function()
				return false
			end,
			get_pid = function()
				return id
			end,
		}
		if on_exit then
			vim.schedule(function()
				on_exit(0, 0)
			end)
		end
		return handle, id
	end
	vim.fn.jobstart = function(command)
		next_job = next_job + 1
		record_effect("jobstart", command)
		return 0
	end
	vim.fn.termopen = function(command)
		next_job = next_job + 1
		record_effect("termopen", command)
		return 0
	end
	local terminal_cmd = vim.cmd.terminal
	vim.cmd.terminal = function(...)
		record_effect("vim.cmd.terminal", { ... })
		return 1
	end
	vim.fn.system = function(command)
		record_effect("system", command)
		return ""
	end
	vim.fn.systemlist = function(command)
		record_effect("systemlist", command)
		return {}
	end
	vim.ui.open = function(uri, callback)
		record_effect("vim.ui.open", uri)
		if callback then
			callback(true)
		end
		return true
	end
	vim.ui.select = function(_, _, callback)
		if callback then
			callback(nil, nil)
		end
	end
	vim.ui.input = function(_, callback)
		if callback then
			callback(nil)
		end
	end
	if description:lower():find("open link from selection", 1, true) then
		vim.fn.mode = function()
			return "v"
		end
	end
	os.execute = function(command)
		record_effect("os.execute", command)
		return true, "exit", 0
	end
	io.popen = function(command)
		record_effect("io.popen", command)
		local output = tostring(command):find("--version", 1, true) and "ripgrep 15.1.0\n" or ""
		return {
			lines = function()
				local read = false
				return function()
					if not read and output ~= "" then
						read = true
						return output:match("([^\n]+)")
					end
					return nil
				end
			end,
			read = function()
				return output
			end,
			close = function()
				return true
			end,
		}
	end
	local dap_methods = {}
	if description:lower():find("debug", 1, true) or description:lower():find("breakpoint", 1, true) then
		local dbg = require("mayon.features.debug")
		dbg.ensure()
		local dap = require("dap")
		for _, name in ipairs({
			"continue",
			"run",
			"run_to_cursor",
			"step_over",
			"step_into",
			"step_out",
			"disconnect",
			"terminate",
			"toggle_breakpoint",
			"set_breakpoint",
			"clear_breakpoints",
			"pause",
		}) do
			if type(dap[name]) == "function" then
				dap_methods[name] = dap[name]
				dap[name] = function(...)
					record_effect("dap." .. name, { ... })
					return true
				end
			end
		end
	end
	local ok, result = xpcall(callback, debug.traceback)
	vim.system = original.system
	vim.fn.jobstart, vim.fn.termopen = original.jobstart, original.termopen
	vim.fn.system, vim.fn.systemlist = original.system_fn, original.systemlist
	vim.ui.open, vim.ui.select, vim.ui.input = original.open, original.select, original.input
	vim.fn.mode = original.mode
	os.execute, io.popen = original.execute, original.popen
	vim.uv.spawn = original.uv_spawn
	if next(dap_methods) then
		local dap = require("dap")
		for name, method in pairs(dap_methods) do
			dap[name] = method
		end
	end
	vim.cmd.terminal = terminal_cmd
	for index = #plugin_boundaries, 1, -1 do
		local entry = plugin_boundaries[index]
		entry.target[entry.name] = entry.fn
	end
	return ok, result
end

local base_buffer = vim.api.nvim_get_current_buf()
local base_window = vim.api.nvim_get_current_win()
local disposable_index = 0
local function prepare_action(description)
	if not vim.api.nvim_buf_is_valid(base_buffer) then
		base_buffer = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(base_buffer, project .. "/recovery.md")
		vim.api.nvim_buf_set_lines(base_buffer, 0, -1, false, { "synthetic recovery" })
	end
	local window = vim.api.nvim_get_current_win()
	if not vim.api.nvim_win_is_valid(window) then
		window = vim.api.nvim_tabpage_list_wins(0)[1]
	end
	vim.api.nvim_set_current_win(window)
	vim.api.nvim_win_set_buf(window, base_buffer)
	vim.cmd.cd(project)
	vim.api.nvim_buf_set_lines(base_buffer, 0, -1, false, {
		"# Offline action fixture",
		"",
		"A small local file for picker and document actions.",
		"https://example.invalid",
	})
	vim.bo[base_buffer].modified = false
	local lower = description:lower()
	if lower == "save buffer" or lower == "format buffer" then
		vim.api.nvim_buf_set_lines(base_buffer, 0, -1, false, { "offline format fixture   ", "second line   " })
		vim.bo[base_buffer].modified = true
	elseif lower == "close buffer" or lower == "close window or buffer" then
		disposable_index = disposable_index + 1
		local target = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(target, project .. "/close-target-" .. disposable_index .. ".md")
		vim.api.nvim_buf_set_lines(target, 0, -1, false, { "disposable" })
		vim.bo[target].modified = false
		if lower == "close window or buffer" then
			vim.cmd("vsplit")
			window = vim.api.nvim_get_current_win()
		end
		vim.api.nvim_win_set_buf(window, target)
	elseif lower == "close other buffers" then
		disposable_index = disposable_index + 1
		local target = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_buf_set_name(target, project .. "/other-target-" .. disposable_index .. ".md")
		vim.api.nvim_buf_set_lines(target, 0, -1, false, { "disposable" })
		vim.bo[target].modified = false
		vim.api.nvim_set_current_buf(base_buffer)
	elseif lower == "open link under cursor" then
		vim.api.nvim_win_set_cursor(window, { 4, 0 })
	elseif lower == "open link from selection" then
		vim.api.nvim_buf_set_mark(base_buffer, "<", 4, 0, {})
		vim.api.nvim_buf_set_mark(base_buffer, ">", 4, 25, {})
		vim.api.nvim_win_set_cursor(window, { 4, 25 })
		vim.api.nvim_feedkeys("v", "nx", false)
		vim.wait(10)
	end
end

local function reset_layout()
	for _, window in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if window ~= base_window then
			vim.api.nvim_win_close(window, true)
		end
	end
	if vim.api.nvim_win_is_valid(base_window) then
		vim.api.nvim_set_current_win(base_window)
		if vim.api.nvim_buf_is_valid(base_buffer) then
			vim.api.nvim_win_set_buf(base_window, base_buffer)
		end
	end
end

-- Seed one closed picker so Resume Last Search exercises the real configured
-- callback with an ordinary local source instead of an empty-history error.
require("snacks").picker.files({ cwd = project })
vim.wait(40)
close_picker()

table.sort(report.mappings, function(a, b)
	local function rank(row)
		local desc = (row.desc or ""):lower()
		return (desc == "close buffer" or desc == "close other buffers" or desc == "close window or buffer") and 10 or 0
	end
	return rank(a) < rank(b)
end)

for _, row in ipairs(report.mappings) do
	if row.disposition == "execute" or row.disposition == "stub" then
		local key = row.mode .. ":" .. row.lhs
		if row.scope == "global" and effective_local[key] then
			row.disposition = "covered_by_buffer_map"
			row.reason = "effective buffer-local mapping with the same mode and lhs is inventoried and exercised"
		end
		if (row.disposition == "execute" or row.disposition == "stub") and not ran[key] then
			ran[key] = true
			local map
			local maps = row.scope == "buffer" and vim.api.nvim_buf_get_keymap(row.buffer, row.mode)
				or vim.api.nvim_get_keymap(row.mode)
			for _, candidate in ipairs(maps) do
				if candidate.lhs == row.lhs then
					map = candidate
					break
				end
			end
			if map and (type(map.callback) == "function" or map.rhs) then
				prepare_action(row.desc or "")
				action_name = row.lhs
				local before_effects = #effects
				local invoke = function()
					if row.desc == "Open Link from Selection" then
						vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(row.lhs, true, false, true), "mx", false)
						vim.wait(30)
					elseif type(map.callback) == "function" then
						map.callback()
					else
						local keys = row.lhs
						if keys:sub(1, 1) == " " then
							keys = (vim.g.mapleader or "\\") .. keys:sub(2)
						end
						vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "mx", false)
						vim.wait(30)
					end
					local delay = (row.desc or ""):lower():find("format", 1, true) and 250 or 150
					vim.wait(delay)
				end
				local ok, err = with_offline_boundaries(invoke, row.desc or "")
				row.result = ok and (row.disposition == "stub" and "stubbed" or "passed") or "error"
				if #effects > before_effects then
					row.stubbed_effects = vim.list_slice(effects, before_effects + 1)
				end
				if not ok then
					row.error = tostring(err)
					capture.record("action", row.lhs .. ": " .. tostring(err), vim.log.levels.ERROR)
				end
				flush_report()
			else
				row.disposition = "skip"
				row.reason = "mapping has no directly callable Lua callback"
			end
			close_picker()
			reset_layout()
			if vim.api.nvim_buf_is_valid(base_buffer) then
				vim.bo[base_buffer].modified = false
				local active = vim.api.nvim_get_current_win()
				if vim.api.nvim_win_is_valid(active) then
					vim.api.nvim_win_set_buf(active, base_buffer)
				end
			end
		elseif row.disposition == "execute" or row.disposition == "stub" then
			row.disposition = "covered_by_equivalent_map"
			row.reason = "the same mode and lhs was already exercised in the isolated fixture"
		end
	end
end

-- Enumerate all custom commands currently registered. Execute only commands
-- whose fixture invocation cannot start a process, request a network service,
-- or mutate files. Contextual commands retain explicit skip reasons.
local execute_commands = {
	EditorStatus = function()
		vim.cmd.EditorStatus()
	end,
	FormatDisable = function()
		vim.cmd.FormatDisable()
	end,
	FormatEnable = function()
		vim.cmd.FormatEnable()
	end,
	AICompletion = function()
		vim.cmd("AICompletion off")
	end,
	Oil = function()
		vim.cmd("Oil " .. vim.fn.fnameescape(project))
	end,
	AerialToggle = function()
		vim.cmd.AerialToggle()
	end,
	AerialClose = function()
		vim.cmd.AerialClose()
	end,
	AerialCloseAll = function()
		vim.cmd.AerialCloseAll()
	end,
	AerialInfo = function()
		vim.cmd.AerialInfo()
	end,
	CodeCompanionChat = function()
		vim.cmd.CodeCompanionChat()
	end,
	ConformInfo = function()
		vim.cmd.ConformInfo()
	end,
	Inspect = function()
		vim.cmd.Inspect()
	end,
	Trouble = function()
		vim.cmd("Trouble qflist toggle")
	end,
	Urls = function()
		vim.cmd.Urls()
	end,
	UrlsBuffer = function()
		vim.cmd.UrlsBuffer()
	end,
}
local function command_inventory(commands, scope, buffer)
	for name, command in pairs(commands) do
		local row = {
			name = name,
			desc = command.desc or command.definition,
			scope = scope,
			buffer = buffer,
			disposition = "skip",
		}
		local run = execute_commands[name]
		if run and scope == "global" then
			local ok, err = with_offline_boundaries(function()
				run()
				vim.wait(100)
			end, name)
			row.disposition = ok and "executed" or "error"
			if not ok then
				row.error = tostring(err)
				capture.record("user_command", name .. ": " .. tostring(err), vim.log.levels.ERROR)
			end
			close_picker()
			reset_layout()
			if vim.api.nvim_buf_is_valid(base_buffer) then
				local active = vim.api.nvim_get_current_win()
				if vim.api.nvim_win_is_valid(active) then
					vim.api.nvim_win_set_buf(active, base_buffer)
				end
			end
		elseif name == "ImagePreview" then
			row.reason = "requires image or formula context; no fixture renderer invoked"
		elseif name == "Urls" or name == "UrlsBuffer" then
			row.reason = "interactive URL selection; picker was not confirmed"
		elseif name == "DebugLuaListen" then
			row.reason = "starts a listener; network/socket action prohibited"
		elseif name:match("^Texlab") then
			row.reason = "requires a TeX document or external texlab/build process"
		elseif
			name:match("CodeCompanion")
			or name:match("Minuet")
			or name:match("Sidekick")
			or name:match("ClaudeCode")
		then
			row.reason = "AI request/CLI boundary; no offline response fixture is bound to this command"
		elseif name:match("Dap") or name:match("Debug") then
			row.reason = "requires a debug target or starts a process/listener; none started"
		elseif name:match("Git") or name:match("Neogit") or name:match("CodeDiff") then
			row.reason = "Git context or repository mutation; no Git subprocess or state change allowed"
		elseif name:match("Format") or name:match("Lint") or name:match("Conform") then
			row.reason = "may start an external formatter/linter; only the buffer-safe toggle commands were executed"
		else
			row.reason = scope == "buffer" and "buffer-local command inventoried; no owning buffer-specific fixture"
				or "no safe no-argument fixture invocation is defined"
		end
		report.commands[#report.commands + 1] = row
	end
end
command_inventory(vim.api.nvim_get_commands({ builtin = false }), "global")
for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
	if vim.api.nvim_buf_is_valid(buffer) then
		local ok, commands = pcall(vim.api.nvim_buf_get_commands, buffer, { builtin = false })
		if ok then
			command_inventory(commands, "buffer", buffer)
		else
			report.commands[#report.commands + 1] = {
				name = "<buffer-command-inventory>",
				scope = "buffer",
				buffer = buffer,
				disposition = "inventory_error",
				error = tostring(commands),
			}
			capture.record("buffer_commands", "nvim_buf_get_commands: " .. tostring(commands), vim.log.levels.ERROR)
		end
	end
end
local seen_mapping = {}
for _, row in ipairs(report.mappings) do
	seen_mapping[table.concat(
		{ row.scope or "", row.buffer or "", row.mode or "", row.lhs or "", row.desc or "" },
		"\0"
	)] =
		true
end
for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
	if vim.api.nvim_buf_is_valid(buffer) then
		for _, mode in ipairs(modes) do
			for _, map in ipairs(vim.api.nvim_buf_get_keymap(buffer, mode)) do
				local key = table.concat({ "buffer", buffer, mode, map.lhs or "", map.desc or "" }, "\0")
				if not seen_mapping[key] then
					seen_mapping[key] = true
					report.mappings[#report.mappings + 1] = {
						scope = "buffer",
						buffer = buffer,
						mode = mode,
						lhs = map.lhs,
						desc = map.desc,
						rhs = map.rhs,
						callback = type(map.callback) == "function",
						disposition = "inventory_only",
						reason = "runtime-generated buffer map discovered after action sweep; no owning-buffer action fixture",
					}
				end
			end
		end
	end
end
table.sort(report.commands, function(a, b)
	return a.name < b.name
end)

local executed_maps, stubbed_maps, map_errors, skipped_maps = 0, 0, 0, 0
for _, row in ipairs(report.mappings) do
	if row.result == "passed" then
		executed_maps = executed_maps + 1
	elseif row.result == "stubbed" then
		stubbed_maps = stubbed_maps + 1
	elseif row.result == "error" then
		map_errors = map_errors + 1
	else
		skipped_maps = skipped_maps + 1
	end
end
local executed_commands, command_errors = 0, 0
for _, row in ipairs(report.commands) do
	if row.disposition == "executed" then
		executed_commands = executed_commands + 1
	elseif row.disposition == "error" then
		command_errors = command_errors + 1
	end
end
report.summary = {
	mappings = #report.mappings,
	which_key_entries = #report.which_key,
	commands = #report.commands,
	executed_mappings = executed_maps + stubbed_maps,
	direct_mappings = executed_maps,
	stubbed_mappings = stubbed_maps,
	skipped_mappings = skipped_maps,
	mapping_errors = map_errors,
	executed_commands = executed_commands,
	command_errors = command_errors,
}
report.stub_effects = effects
vim.fn.writefile({ vim.json.encode(report) }, destination)
assert(map_errors == 0 and command_errors == 0, "self-check action errors; inventory: " .. destination)
assert(executed_maps > 0 and executed_commands > 0, "safe action allowlist did not execute")
