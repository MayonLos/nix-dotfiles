-- Project sessions on top of mini.sessions.
--
-- mini.sessions owns :mksession serialization (MiniSessions.write). This module
-- keeps only what is specific to this config:
--   * sessions are named per cwd + git branch (branch is cached, invalidated on
--     DirChanged/FocusGained/TermLeave/ShellCmdPost, so we do not fork git for
--     every save but still notice a checkout made from a terminal or lazygit),
--   * restore sources the file directly: MiniSessions.read runs
--     `%bwipeout!` first, which would kill terminals and unlisted AI buffers,
--   * a programmatic save never touches the live layout; only the exit
--     autosave closes AI/tool windows first. Tool-only tabs written by a
--     programmatic save are dropped again after restore,
--   * the existing public entry points (setup/load/last/save/path/disable/
--     auto_restore) are preserved for bootstrap and the dashboard.
local M = {}

local has_mini = false
local mini ---@type table|nil

local branch_cache = {} ---@type table<string, string|false>

local save_disabled = false

local function notify(message, level)
	vim.notify("Session: " .. message, level or vim.log.levels.INFO)
end

local function session_dir()
	return vim.fn.stdpath("state") .. "/sessions"
end

-- Resolve the current git branch for a cwd without forking on every call.
-- A false cache entry means "checked, not a git repo".
local function current_branch(cwd)
	cwd = cwd or vim.fn.getcwd()
	if vim.fn.executable("git") == 0 then
		return nil
	end
	local cached = branch_cache[cwd]
	if cached ~= nil then
		return cached or nil
	end
	local ok, result = pcall(function()
		return vim.system({ "git", "-C", cwd, "branch", "--show-current" }, { text = true }):wait()
	end)
	local value = (ok and result and result.code == 0 and vim.trim(result.stdout)) or ""
	branch_cache[cwd] = value ~= "" and value or false
	return value ~= "" and value or nil
end

local function is_default_branch(branch_name)
	return not branch_name or branch_name == "" or branch_name == "main" or branch_name == "master"
end

-- Hash cwd + branch so unusual characters and the legacy '%' encoding never
-- collide (for example, /a/b and /a%b used to share a file).
local function session_name(cwd, branch_name)
	if is_default_branch(branch_name) then
		branch_name = ""
	end
	return vim.fn.sha256(vim.json.encode({ cwd, branch_name })) .. ".vim"
end

-- Filenames of the pre-hash plugin; still read, never written.
local function legacy_session_name(cwd, branch_name)
	local function encode(value)
		return (value:gsub("[\\/:]+", "%%"))
	end
	local name = encode(cwd)
	if not is_default_branch(branch_name) then
		name = name .. "%%" .. encode(branch_name)
	end
	return name .. ".vim"
end

local function session_path(name)
	return session_dir() .. "/" .. name
end

local function current_name()
	return session_name(vim.fn.getcwd(), current_branch())
end

-- Restore order: this branch, then the branch-less (main) session for the same
-- cwd, each first under the hashed name and then under the legacy name.
local function restore_candidate()
	local cwd = vim.fn.getcwd()
	local branch_name = current_branch(cwd)
	local names = { session_name(cwd, branch_name), legacy_session_name(cwd, branch_name) }
	if not is_default_branch(branch_name) then
		names[#names + 1] = session_name(cwd, nil)
		names[#names + 1] = legacy_session_name(cwd, nil)
	end
	for _, name in ipairs(names) do
		local path = session_path(name)
		if vim.fn.filereadable(path) == 1 then
			return path
		end
	end
end

local function has_modified_buffer()
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].modified then
			return true
		end
	end
	return false
end

local function has_file_buffer()
	local util = require("mayon.util")
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and util.is_file_document(buf) then
			return true
		end
	end
	return false
end

-- Close AI and tool windows. Only used by the exit autosave, where changing
-- the layout is harmless; buffers are untouched.
local function close_tool_windows()
	local util = require("mayon.util")
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative == "" then
			local buf = vim.api.nvim_win_get_buf(win)
			if not util.is_document(buf) then
				pcall(vim.api.nvim_win_close, win, false)
			end
		end
	end
end

-- Close tabs without a file document. mksession skips nofile/terminal windows
-- but still writes an empty placeholder for a tab made only of them; this
-- removes those before the exit write and again after a restore.
local function close_tool_tabs()
	local util = require("mayon.util")
	local current = vim.api.nvim_get_current_tabpage()
	for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
		local has_document = false
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
			if
				vim.api.nvim_win_get_config(win).relative == ""
				and util.is_file_document(vim.api.nvim_win_get_buf(win))
			then
				has_document = true
				break
			end
		end
		if not has_document and #vim.api.nvim_list_tabpages() > 1 and vim.api.nvim_tabpage_is_valid(tabpage) then
			pcall(vim.cmd.tabclose, vim.api.nvim_tabpage_get_number(tabpage))
		end
	end
	if vim.api.nvim_tabpage_is_valid(current) then
		vim.api.nvim_set_current_tabpage(current)
	end
end

-- mksession saves every listed buffer, including hidden tool buffers that were
-- never opened in a window. Hide them for the duration of the write and put the
-- user's buffer list back afterwards.
local function suspend_tool_buffers()
	local util = require("mayon.util")
	local suspended = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if
			vim.api.nvim_buf_is_valid(buf)
			and vim.api.nvim_buf_is_loaded(buf)
			and vim.bo[buf].buflisted
			and not util.is_document(buf)
		then
			suspended[#suspended + 1] = buf
			vim.bo[buf].buflisted = false
		end
	end
	return suspended
end

local function restore_tool_buffers(suspended)
	for _, buf in ipairs(suspended) do
		if vim.api.nvim_buf_is_valid(buf) then
			vim.bo[buf].buflisted = true
		end
	end
end

local function save(force, exiting)
	if save_disabled then
		return false
	end
	if not has_file_buffer() or has_modified_buffer() then
		return false
	end
	if #vim.api.nvim_list_uis() == 0 and not force then
		return false
	end
	if exiting then
		close_tool_tabs()
		close_tool_windows()
	end
	vim.fn.mkdir(session_dir(), "p")
	local suspended = suspend_tool_buffers()
	local ok, err
	if has_mini then
		ok, err = pcall(mini.write, current_name(), { force = true, verbose = false })
	else
		ok, err = pcall(vim.cmd, "mksession! " .. vim.fn.fnameescape(session_path(current_name())))
	end
	restore_tool_buffers(suspended)
	if not ok then
		notify("could not save session: " .. tostring(err), vim.log.levels.ERROR)
		return false
	end
	return true
end

-- Source the session file directly. The mksession script itself runs
-- `silent only`/`tabonly`, so hidden terminals and unlisted AI buffers survive.
local function read_session(path)
	if has_modified_buffer() then
		notify("load skipped because a buffer has unsaved changes", vim.log.levels.WARN)
		return false
	end
	if not path then
		notify("no session found for this directory", vim.log.levels.WARN)
		return false
	end
	local entry = vim.api.nvim_get_current_buf()
	local hidden = vim.bo[entry].bufhidden
	-- Native mksession remembers a blank entry buffer and bwipes it at the
	-- end. bufhidden=wipe can delete it earlier, causing E517 on restore.
	local blank_entry = vim.api.nvim_buf_get_name(entry) == ""
		and not vim.bo[entry].modified
		and vim.api.nvim_buf_line_count(entry) == 1
		and vim.api.nvim_buf_get_lines(entry, 0, 1, false)[1] == ""
	if blank_entry then
		vim.bo[entry].bufhidden = "hide"
	end
	local ok, err = pcall(function()
		vim.cmd("silent source " .. vim.fn.fnameescape(path))
		close_tool_tabs()
	end)
	if blank_entry and vim.api.nvim_buf_is_valid(entry) then
		vim.bo[entry].bufhidden = hidden
	end
	if not ok then
		notify("could not restore session: " .. tostring(err), vim.log.levels.ERROR)
		return false
	end
	vim.v.this_session = path
	return true
end

local function load()
	return read_session(restore_candidate())
end

-- Newest `*.vim` file in the session directory; leftovers such as
-- `*.vim.tmp.*` and project-local Session.vim files are ignored.
local function latest_session()
	local newest_path, newest_mtime = nil, -1
	for name, kind in vim.fs.dir(session_dir()) do
		if kind == "file" and name:match("%.vim$") then
			local path = session_path(name)
			local stat = vim.uv.fs_stat(path)
			local stamp = stat and stat.mtime.sec * 1000000000 + stat.mtime.nsec
			if stamp and stamp > newest_mtime then
				newest_path, newest_mtime = path, stamp
			end
		end
	end
	return newest_path
end

local function last()
	if has_modified_buffer() then
		notify("load skipped because a buffer has unsaved changes", vim.log.levels.WARN)
		return false
	end
	local path = latest_session()
	if not path then
		notify("no saved sessions", vim.log.levels.WARN)
		return false
	end
	return read_session(path)
end

local ready = false
function M.setup()
	if ready then
		return
	end
	ready = true
	branch_cache = {}
	-- Keep the pre-mini.sessions layout contract: windows, tabs, sizes and
	-- folds, without serializing every hidden buffer.
	vim.o.sessionoptions = "curdir,tabpages,winsize,folds"

	local ok, loaded = pcall(function()
		require("mayon.config.loader").pack("mini.sessions")
		return require("mini.sessions")
	end)
	-- mini.sessions is an optional payload (absent under `-u NONE`); without it
	-- saving falls back to a plain :mksession of the same file.
	has_mini = ok
	if ok then
		mini = loaded
		mini.setup({
			directory = session_dir(),
			-- Project-local Session.vim files are not ours to pick up or write.
			file = "",
			-- bootstrap/dashboard own the restore decision and VimLeavePre owns
			-- saving, so the tool-window close runs only before the exit write.
			autoread = false,
			autowrite = false,
			force = { read = false, write = true, delete = false },
			verbose = { read = false, write = false, delete = false },
		})
	end

	-- A checkout from a terminal, lazygit or :! must be seen before the exit
	-- autosave picks a session name.
	vim.api.nvim_create_autocmd({ "DirChanged", "FocusGained", "TermLeave", "ShellCmdPost" }, {
		callback = function()
			branch_cache = {}
		end,
	})

	M.load = load
	M.last = last
	M.save = function(force)
		return save(force, false)
	end
	M.path = function()
		return session_path(current_name())
	end
	M.disable = function()
		save_disabled = true
		notify("automatic save disabled for this instance")
	end
	M.auto_restore = function()
		if vim.fn.argc() > 0 then
			return false
		end
		local buf = vim.api.nvim_get_current_buf()
		local dashboard = vim.bo[buf].filetype == "snacks_dashboard"
		if
			(not dashboard and vim.bo[buf].buftype ~= "")
			or vim.api.nvim_buf_get_name(buf) ~= ""
			or vim.bo[buf].modified
		then
			return false
		end
		local path = restore_candidate()
		if not path then
			return false
		end
		if dashboard then
			-- Snacks dashboards are unlisted nofile buffers. Replace the visible
			-- dashboard before sourcing so it cannot survive as an extra tab.
			local scratch = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_win_set_buf(0, scratch)
			-- Switching away can let the dashboard dispose of its buffer itself.
			if vim.api.nvim_buf_is_valid(buf) then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
		end
		return read_session(path)
	end

	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			save(false, true)
		end,
	})
end

return M
