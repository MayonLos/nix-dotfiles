local M = {}

local ready = false
function M.setup()
	if ready then
		return
	end
	ready = true
	local session_dir = vim.fn.stdpath("state") .. "/sessions"
	-- mksession's blank/help/terminal exclusions omit transient windows. Keep
	-- ordinary file windows and filter listed plugin buffers during each save.
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

	local function is_session_document(buf)
		if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
			return false
		end
		local filetype = vim.bo[buf].filetype
		return vim.bo[buf].buftype == ""
			and vim.api.nvim_buf_get_name(buf) ~= ""
			and not filetype:match("^snacks_")
			and not filetype:match("^codecompanion")
			and not filetype:match("^claudecode")
	end

	local function session_tabs()
		local keep, current = {}, vim.api.nvim_tabpage_get_number(vim.api.nvim_get_current_tabpage())
		for index, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
			local has_document = false
			for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
				if
					vim.api.nvim_win_get_config(win).relative == ""
					and is_session_document(vim.api.nvim_win_get_buf(win))
				then
					has_document = true
					break
				end
			end
			keep[index] = has_document
		end
		return keep, current
	end

	-- mksession correctly omits blank/help/terminal and nofile windows, but
	-- still emits a placeholder tab for a tab containing only those windows.
	-- Remove those empty tab sections from its generated script while retaining
	-- all ordinary-file tab and split commands verbatim.
	local function filter_tool_only_tabs(path, keep, current)
		local lines = vim.fn.readfile(path)
		local rewind
		for index, line in ipairs(lines) do
			if line == "tabrewind" then
				rewind = index
				break
			end
		end
		local tab_count, kept_count = #keep, 0
		for _, include in ipairs(keep) do
			if include then
				kept_count = kept_count + 1
			end
		end
		if kept_count == tab_count then
			return true
		end
		if not rewind then
			return false, "mksession omitted tab section markers while tool-only tabs were present"
		end

		local prefix, tabnews = {}, {}
		for index = 1, rewind do
			local line = lines[index]
			if line:match("^tabnew ") then
				tabnews[#tabnews + 1] = line
			elseif line ~= "tabrewind" then
				prefix[#prefix + 1] = line
			end
		end
		if #tabnews ~= tab_count - 1 then
			return false, ("unexpected mksession tab setup: expected %d tabs, found %d"):format(tab_count, #tabnews + 1)
		end
		for index = 1, math.max(0, kept_count - 1) do
			prefix[#prefix + 1] = tabnews[index]
		end
		prefix[#prefix + 1] = "tabrewind"

		local blocks, block, focus_line, footer = {}, {}, nil, {}
		for index = rewind + 1, #lines do
			local line = lines[index]
			if line:match("^tabnext %d+$") then
				focus_line = index
				for tail = index + 1, #lines do
					footer[#footer + 1] = lines[tail]
				end
				break
			elseif line == "tabnext" then
				blocks[#blocks + 1] = block
				block = {}
			else
				block[#block + 1] = line
			end
		end
		if not focus_line then
			return false, "mksession did not write its final tab selection"
		end
		blocks[#blocks + 1] = block
		if #blocks ~= tab_count then
			return false, ("unexpected mksession tab sections: expected %d, found %d"):format(tab_count, #blocks)
		end

		local restored_current = 1
		local kept_index = 0
		for index, include in ipairs(keep) do
			if include then
				kept_index = kept_index + 1
				if index <= current then
					restored_current = kept_index
				end
				if kept_index > 1 then
					prefix[#prefix + 1] = "tabnext"
				end
				vim.list_extend(prefix, blocks[index])
			end
		end
		prefix[#prefix + 1] = "tabnext " .. restored_current
		vim.list_extend(prefix, footer)
		local ok, err = vim.fn.writefile(prefix, path)
		if ok ~= 0 then
			return false, err or "could not rewrite filtered session"
		end
		return true
	end

	local function notify(message, level)
		vim.notify("Session: " .. message, level or vim.log.levels.INFO)
	end

	local function close_restored_tool_tabs()
		-- Older saves can already contain mksession's empty tool placeholders.
		-- Clean the restored layout without rewriting the original session file.
		local keep = session_tabs()
		if not vim.tbl_contains(keep, true) then
			return
		end
		local tabs, active = vim.api.nvim_list_tabpages(), vim.api.nvim_get_current_tabpage()
		for index = #tabs, 1, -1 do
			local tabpage = tabs[index]
			if not keep[index] and vim.api.nvim_tabpage_is_valid(tabpage) then
				local empty, has_normal = true, false
				for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
					local buf = vim.api.nvim_win_get_buf(win)
					local normal = vim.api.nvim_win_get_config(win).relative == ""
					local blank = vim.api.nvim_buf_line_count(buf) == 1
						and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
					has_normal = has_normal or normal
					if vim.bo[buf].modified or vim.bo[buf].buftype == "terminal" or is_session_document(buf) then
						empty = false
					elseif normal then
						empty = empty and blank and vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) == ""
					else
						-- Preserve plugin-created floating content as well.
						empty = empty and blank
					end
				end
				if empty and has_normal then
					vim.cmd("tabclose " .. vim.api.nvim_tabpage_get_number(tabpage))
				end
			end
		end
		if vim.api.nvim_tabpage_is_valid(active) then
			vim.api.nvim_set_current_tabpage(active)
		end
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
			close_restored_tool_tabs()
		end)
		if blank_entry and vim.api.nvim_buf_is_valid(entry) then
			vim.bo[entry].bufhidden = hidden
		end
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
		local keep_tabs, current_tab = session_tabs()
		local has_session_tab = false
		for _, keep in ipairs(keep_tabs) do
			has_session_tab = has_session_tab or keep
		end
		if not has_session_tab then
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
		local filtered, filter_error = filter_tool_only_tabs(temp_path, keep_tabs, current_tab)
		if not filtered then
			vim.uv.fs_unlink(temp_path)
			notify("could not filter tool-only tabs: " .. tostring(filter_error), vim.log.levels.ERROR)
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
