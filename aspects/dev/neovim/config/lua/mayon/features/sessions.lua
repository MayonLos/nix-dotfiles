local M = {}

local ready = false
function M.setup()
	if ready then
		return
	end
	ready = true
	local session_dir = vim.fn.stdpath("state") .. "/sessions"
	-- Keep ordinary file windows and their layout. The buffer list is filtered
	-- for the duration of mksession below so plugin-owned panes never leak into
	-- a project session.
	local session_options = "curdir,tabpages,winsize,folds"
	local mtime_baselines = {}
	local save_disabled = false

	vim.o.sessionoptions = session_options

	local function encode(value)
		return value:gsub("[\\/:]+", "%%")
	end

	-- Read the previous plugin's filenames, but avoid its ambiguous '%' path
	-- encoding for new saves (for example, /a/b and /a%b used to collide).
	local function legacy_session_path(cwd, branch)
		local name = encode(cwd)
		if branch and branch ~= "" and branch ~= "main" and branch ~= "master" then
			name = name .. "%%" .. encode(branch)
		end
		return session_dir .. "/" .. name .. ".vim"
	end

	local function session_path(cwd, branch)
		if not branch or branch == "main" or branch == "master" then
			branch = ""
		end
		return session_dir .. "/" .. vim.fn.sha256(vim.json.encode({ cwd, branch })) .. ".vim"
	end

	local function current_branch(cwd)
		if vim.fn.executable("git") == 0 then
			return nil
		end
		local ok, result = pcall(function()
			return vim.system({ "git", "-C", cwd, "branch", "--show-current" }, { text = true }):wait()
		end)
		if not ok or result.code ~= 0 then
			return nil
		end
		return vim.trim(result.stdout)
	end

	local function mtime(path)
		local stat = vim.uv.fs_stat(path)
		if not stat then
			return false
		end
		return tostring(stat.mtime.sec) .. ":" .. tostring(stat.mtime.nsec)
	end

	local function current_session_path()
		local cwd = vim.fn.getcwd()
		return session_path(cwd, current_branch(cwd))
	end

	local function snapshot_current_session()
		local path = current_session_path()
		if mtime_baselines[path] == nil then
			mtime_baselines[path] = mtime(path)
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
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if
				vim.api.nvim_buf_is_loaded(buf)
				and vim.bo[buf].buftype == ""
				and vim.api.nvim_buf_get_name(buf) ~= ""
			then
				return true
			end
		end
		return false
	end

	local function notify(message, level)
		vim.notify("Session: " .. message, level or vim.log.levels.INFO)
	end

	local function load_session(path)
		if has_modified_buffer() then
			notify("load skipped because a buffer has unsaved changes", vim.log.levels.WARN)
			return
		end
		if not path or path == "" or vim.fn.filereadable(path) == 0 then
			notify("no session found for this directory", vim.log.levels.WARN)
			return
		end
		local ok, err = pcall(vim.cmd, "silent source " .. vim.fn.fnameescape(path))
		if not ok then
			notify("could not restore session: " .. tostring(err), vim.log.levels.ERROR)
		end
	end

	local function load_current_session()
		local cwd = vim.fn.getcwd()
		local branch = current_branch(cwd)
		local paths = { session_path(cwd, branch), legacy_session_path(cwd, branch) }
		if branch and branch ~= "" and branch ~= "main" and branch ~= "master" then
			table.insert(paths, session_path(cwd, nil))
			table.insert(paths, legacy_session_path(cwd, nil))
		end
		for _, path in ipairs(paths) do
			if vim.fn.filereadable(path) == 1 then
				load_session(path)
				return
			end
		end
		load_session(nil)
	end

	local function load_last_session()
		local scan = vim.uv.fs_scandir(session_dir)
		if not scan then
			notify("no saved sessions", vim.log.levels.WARN)
			return
		end
		local newest_path
		local newest_mtime = -1
		while true do
			local name, kind = vim.uv.fs_scandir_next(scan)
			if not name then
				break
			end
			if kind == "file" and name:match("%.vim$") then
				local path = session_dir .. "/" .. name
				local stat = vim.uv.fs_stat(path)
				if stat and stat.mtime.sec * 1000000000 + stat.mtime.nsec > newest_mtime then
					newest_path = path
					newest_mtime = stat.mtime.sec * 1000000000 + stat.mtime.nsec
				end
			end
		end
		load_session(newest_path)
	end

	local function save_session_impl(force)
		if save_disabled or (#vim.api.nvim_list_uis() == 0 and not force) then
			return false
		end
		if not has_file_buffer() or has_modified_buffer() then
			return false
		end

		local path = current_session_path()
		local baseline = mtime_baselines[path]
		if baseline == nil then
			baseline = mtime(path)
			mtime_baselines[path] = baseline
		end
		if mtime(path) ~= baseline then
			notify("save skipped because this session changed in another Neovim instance", vim.log.levels.WARN)
			return false
		end

		vim.fn.mkdir(session_dir, "p")
		local temp_path = path .. ".tmp." .. vim.fn.getpid() .. "." .. tostring(vim.uv.hrtime())
		local listed = {}
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			if vim.api.nvim_buf_is_loaded(buf) then
				local filetype = vim.bo[buf].filetype
				local special = vim.bo[buf].buftype ~= ""
					or filetype:match("^snacks_")
					or filetype:match("^codecompanion")
					or filetype:match("^claudecode")
					or vim.b[buf].snacks_picker
					or vim.b[buf].snacks_terminal
				if special and vim.bo[buf].buflisted then
					listed[buf] = true
					vim.bo[buf].buflisted = false
				end
			end
		end
		local ok, err = pcall(vim.cmd, "mksession! " .. vim.fn.fnameescape(temp_path))
		for buf in pairs(listed) do
			if vim.api.nvim_buf_is_valid(buf) then
				vim.bo[buf].buflisted = true
			end
		end
		if not ok then
			vim.uv.fs_unlink(temp_path)
			notify("could not save session: " .. tostring(err), vim.log.levels.ERROR)
			return false
		end

		-- Check again after writing, immediately before the atomic replacement.
		if mtime(path) ~= baseline then
			vim.uv.fs_unlink(temp_path)
			notify("save skipped because this session changed in another Neovim instance", vim.log.levels.WARN)
			return false
		end
		local renamed, rename_err = vim.uv.fs_rename(temp_path, path)
		if not renamed then
			vim.uv.fs_unlink(temp_path)
			notify("could not replace session file: " .. tostring(rename_err), vim.log.levels.ERROR)
			return false
		end
		mtime_baselines[path] = mtime(path)
		return true
	end

	-- workspace.schedule recreates the native tool tabs on BufEnter/WinEnter.
	-- Keep those callbacks from racing mksession or a session source, and
	-- restore the caller's prior state even when Vim reports an error.
	local function with_session_guard(callback)
		local previous = vim.g.mayon_session_saving
		vim.g.mayon_session_saving = true
		local ok, result = xpcall(callback, debug.traceback)
		vim.g.mayon_session_saving = previous
		if not ok then
			error(result)
		end
		return result
	end

	local function save_session(force)
		return with_session_guard(function()
			return save_session_impl(force)
		end)
	end

	vim.keymap.set("n", "<leader>ps", load_current_session, { desc = "Load Project Session" })
	vim.keymap.set("n", "<leader>pl", load_last_session, { desc = "Load Last Session" })
	vim.keymap.set("n", "<leader>pd", function()
		save_disabled = true
		notify("automatic save disabled for this instance")
	end, { desc = "Pause Session Saving" })

	vim.api.nvim_create_autocmd("DirChanged", { callback = snapshot_current_session })
	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			save_session()
		end,
	})
	M.load = load_current_session
	M.last = load_last_session
	M.save = save_session
	M.path = current_session_path
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
		local cwd, branch = vim.fn.getcwd(), current_branch(vim.fn.getcwd())
		local candidates = { session_path(cwd, branch), legacy_session_path(cwd, branch) }
		if branch and branch ~= "" and branch ~= "main" and branch ~= "master" then
			table.insert(candidates, session_path(cwd, nil))
			table.insert(candidates, legacy_session_path(cwd, nil))
		end
		local has_session = false
		for _, path in ipairs(candidates) do
			if vim.fn.filereadable(path) == 1 then
				has_session = true
				break
			end
		end
		if not has_session then
			return false
		end
		return with_session_guard(function()
			if dashboard then
				-- Snacks dashboards are unlisted nofile buffers. Replace the visible
				-- dashboard before sourcing the project windows so it cannot survive
				-- as an extra tab in the restored session.
				local scratch = vim.api.nvim_create_buf(false, true)
				vim.api.nvim_win_set_buf(0, scratch)
				-- Switching away can let the dashboard plugin dispose of its buffer
				-- synchronously (or from a scheduled cleanup). Never delete a stale id.
				if vim.api.nvim_buf_is_valid(buf) then
					vim.api.nvim_buf_delete(buf, { force = true })
				end
			end
			load_current_session()
			return true
		end)
	end
	M.disable = function()
		save_disabled = true
		notify("automatic save disabled for this instance")
	end
	snapshot_current_session()
end

return M
