-- Small file-management helpers used by the native Nvim configuration.
-- This module intentionally has no plugin or shell-string dependency.
local M = {}

local api = vim.api
local uv = vim.uv or vim.loop
local tree = { expanded = {}, entries = {}, root = nil, win = nil, target_win = nil, show_hidden = false }

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, { title = "Files" })
end

local function normalize(path)
	return vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
end

local function is_dir(path)
	local stat = uv.fs_stat(path)
	return stat and stat.type == "directory"
end

local function listed_buffers(except)
	local result = {}
	for _, buf in ipairs(api.nvim_list_bufs()) do
		if buf ~= except and api.nvim_buf_is_valid(buf) and vim.bo[buf].buflisted then
			result[#result + 1] = buf
		end
	end
	table.sort(result, function(a, b)
		local current = api.nvim_get_current_buf()
		if a == current then
			return true
		end
		if b == current then
			return false
		end
		return a < b
	end)
	return result
end

local function display_name(buf)
	local name = api.nvim_buf_get_name(buf)
	return name == "" and "[No Name]" or vim.fn.fnamemodify(name, ":~:.")
end

-- Replace a buffer in every window before deleting it, so the split layout
-- survives even when the target is visible more than once.
function M.bufdelete(opts)
	opts = opts or {}
	local buf = opts.buf or api.nvim_get_current_buf()
	if not api.nvim_buf_is_valid(buf) then
		return false
	end

	local function delete(force)
		local replacement = listed_buffers(buf)[1]
		if not replacement then
			replacement = api.nvim_create_buf(true, false)
			vim.bo[replacement].bufhidden = "wipe"
		end
		for _, win in ipairs(api.nvim_list_wins()) do
			if api.nvim_win_is_valid(win) and api.nvim_win_get_buf(win) == buf then
				api.nvim_win_set_buf(win, replacement)
			end
		end
		local ok, err = pcall(api.nvim_buf_delete, buf, { force = force })
		if not ok then
			notify("Could not close " .. display_name(buf) .. ": " .. tostring(err), vim.log.levels.ERROR)
			return false
		end
		return true
	end

	if not vim.bo[buf].modified then
		return delete(false)
	end
	vim.ui.select({ "Save and close", "Discard changes", "Cancel" }, {
		prompt = "Unsaved changes in " .. display_name(buf),
	}, function(choice)
		if choice == "Save and close" then
			local ok = pcall(api.nvim_buf_call, buf, function()
				vim.cmd("write")
			end)
			if not ok or not api.nvim_buf_is_valid(buf) or vim.bo[buf].modified then
				notify("Save failed; buffer was kept", vim.log.levels.ERROR)
				return
			end
			delete(false)
		elseif choice == "Discard changes" then
			delete(true)
		end
	end)
	return true
end

local function explorer_buf()
	if tree.buf and api.nvim_buf_is_valid(tree.buf) then
		return tree.buf
	end
	tree.buf = api.nvim_create_buf(false, true)
	vim.bo[tree.buf].buftype = "nofile"
	vim.bo[tree.buf].bufhidden = "hide"
	vim.bo[tree.buf].swapfile = false
	vim.bo[tree.buf].filetype = "mayon-file-tree"
	return tree.buf
end

local function scan_dir(path, depth, entries)
	local items = {}
	local ok, iter = pcall(uv.fs_scandir, path)
	if not ok or not iter then
		return
	end
	while true do
		local name, kind = uv.fs_scandir_next(iter)
		if not name then
			break
		end
		if tree.show_hidden or name:sub(1, 1) ~= "." then
			local full = path .. "/" .. name
			if kind == "directory" or kind == "link" and is_dir(full) then
				items[#items + 1] = { name = name, path = full, dir = true }
			else
				items[#items + 1] = { name = name, path = full, dir = false }
			end
		end
	end
	table.sort(items, function(a, b)
		if a.dir ~= b.dir then
			return a.dir
		end
		return a.name:lower() < b.name:lower()
	end)
	for _, item in ipairs(items) do
		entries[#entries + 1] = { path = item.path, dir = item.dir, depth = depth, name = item.name }
		if item.dir and tree.expanded[item.path] then
			scan_dir(item.path, depth + 1, entries)
		end
	end
end

local function render_tree()
	if not tree.buf or not api.nvim_buf_is_valid(tree.buf) then
		return
	end
	tree.entries = {}
	local lines = { vim.fn.fnamemodify(tree.root, ":~:.") .. "/" }
	tree.entries[1] = { path = tree.root, dir = true, root = true }
	scan_dir(tree.root, 0, tree.entries)
	for i = 2, #tree.entries do
		local entry = tree.entries[i]
		local indent = string.rep("  ", entry.depth)
		local marker = entry.dir and (tree.expanded[entry.path] and "▾ " or "▸ ") or "  "
		lines[#lines + 1] = indent .. marker .. entry.name .. (entry.dir and "/" or "")
	end
	vim.bo[tree.buf].modifiable = true
	api.nvim_buf_set_lines(tree.buf, 0, -1, false, lines)
	vim.bo[tree.buf].modifiable = false
end

local function entry_at_cursor()
	local row = api.nvim_win_get_cursor(0)[1]
	return tree.entries[row]
end

local function close_tree()
	if tree.win and api.nvim_win_is_valid(tree.win) then
		api.nvim_win_close(tree.win, true)
	end
	tree.win = nil
end

local function scratch_dir()
	return vim.fn.stdpath("data") .. "/mayon-scratch"
end

local function stat_fingerprint(path)
	local stat = uv.fs_lstat(path)
	if not stat then
		return nil
	end
	return table.concat({
		tostring(stat.type),
		tostring(stat.dev),
		tostring(stat.ino),
		tostring(stat.mode),
		tostring(stat.size),
		tostring(stat.mtime and stat.mtime.sec),
		tostring(stat.mtime and stat.mtime.nsec),
		tostring(stat.ctime and stat.ctime.sec),
		tostring(stat.ctime and stat.ctime.nsec),
	}, ":")
end

-- Changing a buffer name after an OS-level rename makes Neovim treat the
-- moved file as an existing destination and its first normal write raises
-- E13. Allow one guarded write against the exact inode/version moved above;
-- an intervening external edit is left untouched for the user to resolve.
local function arm_renamed_write(buf, path)
	local expected = stat_fingerprint(path)
	if not expected then
		return
	end
	local prior = vim.b[buf].mayon_rename_write_autocmd
	if prior then
		pcall(api.nvim_del_autocmd, prior)
	end
	local buftype = vim.b[buf].mayon_original_buftype
	if buftype == nil then
		buftype = vim.bo[buf].buftype
		vim.b[buf].mayon_original_buftype = buftype
	end
	vim.bo[buf].buftype = "acwrite"
	local function register()
		local id
		id = api.nvim_create_autocmd("BufWriteCmd", {
			buffer = buf,
			desc = "Safely write a buffer after native file rename",
			callback = function()
				if api.nvim_buf_get_name(buf) ~= path then
					notify(
						"Buffer path changed again; use the file tree rename action before saving.",
						vim.log.levels.ERROR
					)
					return
				end
				if vim.v.cmdbang ~= 1 and stat_fingerprint(path) ~= expected then
					notify(
						"File changed outside Neovim; buffer kept. Use :write! only to override deliberately.",
						vim.log.levels.ERROR
					)
					return
				end
				api.nvim_del_autocmd(id)
				vim.b[buf].mayon_rename_write_autocmd = nil
				vim.bo[buf].buftype = buftype
				local ok, err = pcall(api.nvim_buf_call, buf, function()
					api.nvim_exec_autocmds("BufWritePre", { buffer = buf })
					vim.cmd("write!")
					api.nvim_exec_autocmds("BufWritePost", { buffer = buf })
				end)
				if not ok then
					vim.bo[buf].buftype = "acwrite"
					register()
					notify("Could not write renamed file: " .. tostring(err), vim.log.levels.ERROR)
				else
					vim.b[buf].mayon_original_buftype = nil
				end
			end,
		})
		vim.b[buf].mayon_rename_write_autocmd = id
	end
	register()
end

local function open_entry()
	local entry = entry_at_cursor()
	if not entry then
		return
	end
	if entry.dir then
		tree.expanded[entry.path] = not tree.expanded[entry.path]
		render_tree()
		return
	end
	local path, win = entry.path, tree.target_win
	close_tree()
	if win and api.nvim_win_is_valid(win) then
		api.nvim_set_current_win(win)
	end
	vim.cmd.edit(vim.fn.fnameescape(path))
end

local function parent_dir()
	local entry = entry_at_cursor()
	if not entry then
		return
	end
	if entry.root then
		local parent = vim.fs.dirname(tree.root)
		if parent and parent ~= tree.root then
			tree.root = parent
			tree.expanded[parent] = true
			render_tree()
		end
		return
	end
	if entry.dir and entry.path ~= tree.root and tree.expanded[entry.path] then
		tree.expanded[entry.path] = false
	else
		local parent = vim.fs.dirname(entry.path)
		if parent and parent ~= entry.path then
			tree.expanded[parent] = false
		end
	end
	render_tree()
end

local function set_tree_mappings(buf)
	local function map(lhs, rhs, desc)
		vim.keymap.set("n", lhs, rhs, { buffer = buf, silent = true, nowait = true, desc = desc })
	end
	map("<CR>", open_entry, "Open or expand")
	map("l", open_entry, "Open or expand")
	map("h", parent_dir, "Collapse or parent")
	map("<BS>", parent_dir, "Collapse or parent")
	map("r", function()
		local entry = entry_at_cursor()
		if entry and not entry.root then
			M.rename(entry.path)
		else
			notify("Select a child item to rename", vim.log.levels.WARN)
		end
	end, "Rename file or directory")
	map("R", function()
		render_tree()
	end, "Refresh tree")
	map("H", function()
		tree.show_hidden = not tree.show_hidden
		render_tree()
		notify(tree.show_hidden and "Hidden files shown" or "Hidden files hidden")
	end, "Toggle hidden files")
	map("a", function()
		local entry = entry_at_cursor()
		local parent = entry and (entry.dir and entry.path or vim.fs.dirname(entry.path)) or tree.root
		vim.ui.input({ prompt = "Create file or directory (end directory with /): ", default = "" }, function(input)
			if not input or input == "" then
				return
			end
			local directory = input:sub(-1) == "/"
			local name = input:gsub("/$", "")
			if name == "" or name:find("[/\\]") then
				notify("Enter a single name", vim.log.levels.ERROR)
				return
			end
			local path = parent .. "/" .. name
			if uv.fs_lstat(path) then
				notify("Already exists: " .. path, vim.log.levels.ERROR)
				return
			end
			local ok, err
			if directory then
				ok, err = uv.fs_mkdir(path, 493)
			else
				local fd
				fd, err = uv.fs_open(path, "wx", 420)
				ok = fd ~= nil
				if fd then
					uv.fs_close(fd)
				end
			end
			if not ok then
				notify("Create failed: " .. tostring(err), vim.log.levels.ERROR)
				return
			end
			if directory then
				tree.expanded[path] = true
			end
			render_tree()
		end)
	end, "Create file or directory")
	map("d", function()
		local entry = entry_at_cursor()
		if not entry or entry.root then
			notify("Select a child item to move to trash", vim.log.levels.WARN)
			return
		end
		vim.ui.select(
			{ "Move to trash", "Cancel" },
			{ prompt = "Move " .. entry.name .. " to trash?" },
			function(choice)
				if choice ~= "Move to trash" then
					return
				end
				local trash = vim.fn.exepath("trash-put")
				if trash == "" then
					trash = vim.fn.exepath("trash")
				end
				if trash == "" then
					notify("trash-cli command is unavailable; nothing was deleted", vim.log.levels.ERROR)
					return
				end
				local result = vim.system({ trash, entry.path }, { text = true }):wait()
				if result.code ~= 0 then
					notify("Could not move item to trash: " .. (result.stderr or ""), vim.log.levels.ERROR)
					return
				end
				tree.expanded[entry.path] = nil
				render_tree()
			end
		)
	end, "Move to trash")
	map("y", function()
		local entry = entry_at_cursor()
		if not entry then
			return
		end
		vim.fn.setreg("+", entry.path)
		notify("Copied path: " .. entry.path)
	end, "Copy absolute path")
	map("q", close_tree, "Close tree")
end

function M.explorer(opts)
	opts = opts or {}
	local current = api.nvim_get_current_win()
	local current_buf = api.nvim_get_current_buf()
	local path = opts.cwd or api.nvim_buf_get_name(current_buf)
	if path == "" then
		path = uv.cwd()
	end
	path = normalize(path)
	if not is_dir(path) then
		path = vim.fs.dirname(path)
	end
	if not path or not is_dir(path) then
		notify("Directory does not exist", vim.log.levels.ERROR)
		return
	end
	tree.root = path
	tree.target_win = (tree.win and current ~= tree.win) and current or (tree.target_win or current)
	if not tree.expanded[path] then
		tree.expanded[path] = true
	end
	local buf = explorer_buf()
	render_tree()
	if tree.win and api.nvim_win_is_valid(tree.win) then
		api.nvim_set_current_win(tree.win)
		return
	end
	vim.cmd("topleft 35vnew")
	tree.win = api.nvim_get_current_win()
	api.nvim_win_set_buf(tree.win, buf)
	api.nvim_win_set_width(tree.win, math.min(45, math.max(24, math.floor(vim.o.columns * 0.24))))
	vim.wo[tree.win].number = false
	vim.wo[tree.win].relativenumber = false
	vim.wo[tree.win].signcolumn = "no"
	vim.wo[tree.win].winfixwidth = true
	set_tree_mappings(buf)
end

function M.setup()
	-- Directory arguments are handled by this tree instead of the bundled netrw.
	vim.g.loaded_netrw = 1
	vim.g.loaded_netrwPlugin = 1
	local group = api.nvim_create_augroup("MayonFileTreeStartup", { clear = true })
	local function open_directory_buffer(buf)
		if not api.nvim_buf_is_valid(buf) or vim.b[buf].mayon_tree_opened then
			return
		end
		local name = api.nvim_buf_get_name(buf)
		if name == "" or not is_dir(name) then
			return
		end
		vim.b[buf].mayon_tree_opened = true
		local source_win = api.nvim_get_current_win()
		M.explorer({ cwd = name })
		if tree.target_win and api.nvim_win_is_valid(tree.target_win) and api.nvim_buf_is_valid(buf) then
			local empty = api.nvim_create_buf(true, false)
			api.nvim_win_set_buf(tree.target_win, empty)
			pcall(api.nvim_buf_delete, buf, { force = true })
		elseif source_win and api.nvim_win_is_valid(source_win) and api.nvim_buf_is_valid(buf) then
			pcall(api.nvim_buf_delete, buf, { force = true })
		end
	end
	api.nvim_create_autocmd("VimEnter", {
		group = group,
		callback = function()
			vim.schedule(function()
				open_directory_buffer(api.nvim_get_current_buf())
			end)
		end,
	})
	api.nvim_create_autocmd("BufEnter", {
		group = group,
		callback = function(args)
			vim.schedule(function()
				open_directory_buffer(args.buf)
			end)
		end,
	})
	local scratch_group = api.nvim_create_augroup("MayonScratchPersistence", { clear = true })
	local function save_scratch(buf)
		if not api.nvim_buf_is_valid(buf) or not vim.bo[buf].modified then
			return
		end
		local name = api.nvim_buf_get_name(buf)
		local prefix = vim.fs.normalize(scratch_dir()) .. "/"
		if name:sub(1, #prefix) ~= prefix then
			return
		end
		pcall(api.nvim_buf_call, buf, function()
			vim.cmd("silent write")
		end)
	end
	api.nvim_create_autocmd({ "BufLeave", "BufHidden" }, {
		group = scratch_group,
		callback = function(args)
			vim.schedule(function()
				save_scratch(args.buf)
			end)
		end,
	})
	api.nvim_create_autocmd("VimLeavePre", {
		group = scratch_group,
		callback = function()
			for _, buf in ipairs(api.nvim_list_bufs()) do
				save_scratch(buf)
			end
		end,
	})
end

local function file_uri(path)
	return vim.uri_from_fname(path)
end

function M.rename(path)
	local buf = api.nvim_get_current_buf()
	local old = path or api.nvim_buf_get_name(buf)
	if old == "" then
		notify("Current buffer has no file", vim.log.levels.WARN)
		return
	end
	old = normalize(old)
	vim.ui.input({ prompt = "Rename to: ", default = old }, function(input)
		if not input or input == "" then
			return
		end
		local new = normalize(input)
		if new == old then
			return
		end
		if uv.fs_lstat(new) then
			notify("Target already exists: " .. new, vim.log.levels.ERROR)
			return
		end
		for _, candidate in ipairs(api.nvim_list_bufs()) do
			if api.nvim_buf_is_valid(candidate) then
				local candidate_name = api.nvim_buf_get_name(candidate)
				if candidate_name == new or candidate_name:sub(1, #new + 1) == new .. "/" then
					notify("Target is already open in a buffer: " .. candidate_name, vim.log.levels.ERROR)
					return
				end
			end
		end
		if not is_dir(vim.fs.dirname(new)) then
			notify("Parent directory does not exist", vim.log.levels.ERROR)
			return
		end

		local renaming_directory = is_dir(old)
		local buffers, clients, changes = {}, {}, {}
		for _, candidate in ipairs(api.nvim_list_bufs()) do
			local candidate_name = api.nvim_buf_is_valid(candidate) and api.nvim_buf_get_name(candidate) or ""
			if candidate_name == old or (renaming_directory and candidate_name:sub(1, #old + 1) == old .. "/") then
				buffers[#buffers + 1] = candidate
				for _, client in ipairs(vim.lsp.get_clients({ bufnr = candidate })) do
					clients[client.id] = client
				end
			end
		end
		for _, client in pairs(clients) do
			if client:supports_method("workspace/willRenameFiles") then
				local response = client:request_sync("workspace/willRenameFiles", {
					files = { { oldUri = file_uri(old), newUri = file_uri(new) } },
				}, 1500, buffers[1] or buf)
				if response and response.result then
					changes[#changes + 1] = { client = client, edit = response.result }
				end
			end
		end

		local ok, err = uv.fs_rename(old, new)
		if not ok then
			notify("Rename failed: " .. tostring(err), vim.log.levels.ERROR)
			return
		end
		for _, change in ipairs(changes) do
			vim.lsp.util.apply_workspace_edit(change.edit, change.client.offset_encoding)
		end
		for _, candidate in ipairs(buffers) do
			if api.nvim_buf_is_valid(candidate) then
				local candidate_name = api.nvim_buf_get_name(candidate)
				local suffix = candidate_name == old and "" or candidate_name:sub(#old + 1)
				local target = new .. suffix
				api.nvim_buf_set_name(candidate, target)
				if not renaming_directory or target ~= new then
					arm_renamed_write(candidate, target)
				end
			end
		end
		local files = { files = { { oldUri = file_uri(old), newUri = file_uri(new) } } }
		for _, client in pairs(clients) do
			if client:supports_method("workspace/didRenameFiles") then
				client:notify("workspace/didRenameFiles", files)
			end
		end
		notify("Renamed to " .. vim.fn.fnamemodify(new, ":~:.") .. " (buffer changes kept)")
	end)
end

function M.scratch()
	local dir = scratch_dir()
	vim.fn.mkdir(dir, "p", "0700")
	local name = os.date("%Y%m%d-%H%M%S") .. "-" .. tostring(uv.hrtime()) .. ".md"
	local path = dir .. "/" .. name
	local fd, err = uv.fs_open(path, "wx", 384)
	if not fd then
		notify("Cannot create scratch file: " .. tostring(err), vim.log.levels.ERROR)
		return
	end
	uv.fs_close(fd)
	vim.cmd.edit(vim.fn.fnameescape(path))
	vim.bo.filetype = "markdown"
	vim.bo.buflisted = true
	return api.nvim_get_current_buf()
end

function M.scratch_select()
	local dir = scratch_dir()
	local entries = {}
	local ok, iter = pcall(uv.fs_scandir, dir)
	if ok and iter then
		while true do
			local name, kind = uv.fs_scandir_next(iter)
			if not name then
				break
			end
			if kind == "file" and name:match("%.md$") then
				entries[#entries + 1] = name
			end
		end
	end
	table.sort(entries, function(a, b)
		return a > b
	end)
	if #entries == 0 then
		notify("No scratch notes yet", vim.log.levels.INFO)
		return
	end
	vim.ui.select(entries, { prompt = "Scratch notes" }, function(choice)
		if choice then
			vim.cmd.edit(vim.fn.fnameescape(dir .. "/" .. choice))
		end
	end)
end

local function run(argv, cwd)
	local result = vim.system(argv, { cwd = cwd, text = true }):wait()
	if result.code ~= 0 then
		return nil, result.stderr
	end
	return (result.stdout or ""):gsub("[\r\n]+$", "")
end

function M.lazygit()
	local command = vim.fn.exepath("lazygit")
	if command == "" then
		notify("lazygit is not installed", vim.log.levels.ERROR)
		return
	end
	local buf = api.nvim_create_buf(false, true)
	local width, height = math.max(60, math.floor(vim.o.columns * 0.88)), math.max(16, math.floor(vim.o.lines * 0.84))
	width, height = math.min(width, vim.o.columns - 4), math.min(height, vim.o.lines - 4)
	local win = api.nvim_open_win(buf, true, {
		relative = "editor",
		style = "minimal",
		border = "rounded",
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2) - 1,
		col = math.floor((vim.o.columns - width) / 2),
	})
	vim.bo[buf].bufhidden = "wipe"
	vim.fn.termopen({ command }, {
		cwd = run({ "git", "rev-parse", "--show-toplevel" }, uv.cwd()) or uv.cwd(),
		on_exit = function()
			vim.schedule(function()
				if api.nvim_win_is_valid(win) then
					api.nvim_win_close(win, true)
				end
			end)
		end,
	})
	vim.cmd.startinsert()
end

local function url_encode(value)
	return (value:gsub("([^%w%-%._~/])", function(char)
		return string.format("%%%02X", char:byte())
	end))
end

local function normalize_remote(remote)
	remote = remote:gsub("%.git$", "")
	remote = remote:gsub("^git@([^:]+):", "https://%1/")
	remote = remote:gsub("^ssh://git@", "https://")
	remote = remote:gsub("^ssh://([^/]+)/", "https://%1/")
	remote = remote:gsub("^https://[^@]+@", "https://")
	return remote:gsub("^git%+https://", "https://")
end

function M.gitbrowse()
	local buf = api.nvim_get_current_buf()
	local file = api.nvim_buf_get_name(buf)
	local cwd = file ~= "" and vim.fs.dirname(file) or uv.cwd()
	local root = run({ "git", "-C", cwd, "rev-parse", "--show-toplevel" })
	if not root then
		notify("Current file is not in a Git repository", vim.log.levels.WARN)
		return
	end
	local remotes = run({ "git", "-C", root, "remote", "-v" }) or ""
	local remote
	for line in remotes:gmatch("[^\n]+") do
		local name, url, kind = line:match("^(%S+)%s+(%S+)%s+%((%a+)%)$")
		if kind == "fetch" and (name == "origin" or not remote) then
			remote = url
			if name == "origin" then
				break
			end
		end
	end
	if not remote then
		notify("No Git remote found", vim.log.levels.WARN)
		return
	end
	local base = normalize_remote(remote):gsub("/$", "")
	local branch = run({ "git", "-C", root, "branch", "--show-current" })
	if not branch or branch == "" then
		branch = run({ "git", "-C", root, "rev-parse", "HEAD" })
	end
	local rel = file ~= "" and run({ "git", "-C", root, "ls-files", "--full-name", "--", file }) or nil
	if not rel or rel == "" then
		notify("Current file is not tracked by Git", vim.log.levels.WARN)
		return
	end
	local line_start, line_end = api.nvim_win_get_cursor(0)[1], api.nvim_win_get_cursor(0)[1]
	local mode = vim.fn.mode(1)
	if mode == "v" or mode == "V" or mode == "\22" then
		local start = vim.fn.getpos("v")[2]
		line_start, line_end = math.min(start, line_end), math.max(start, line_end)
	end
	local encoded_branch, encoded_file = url_encode(branch), url_encode(rel)
	local host = base:match("^https?://([^/]+)") or ""
	local url
	if host:match("github%.com$") then
		url = base .. "/blob/" .. encoded_branch .. "/" .. encoded_file .. "#L" .. line_start
		if line_end > line_start then
			url = url .. "-L" .. line_end
		end
	elseif host:match("gitlab%.com$") or host:find("gitlab", 1, true) then
		url = base .. "/-/blob/" .. encoded_branch .. "/" .. encoded_file .. "#L" .. line_start
		if line_end > line_start then
			url = url .. "-" .. line_end
		end
	elseif host:match("bitbucket%.org$") then
		url = base .. "/src/" .. encoded_branch .. "/" .. encoded_file .. "#lines-" .. line_start
		if line_end > line_start then
			url = url .. "-L" .. line_end
		end
	else
		url = base .. "/blob/" .. encoded_branch .. "/" .. encoded_file .. "#L" .. line_start
		if line_end > line_start then
			url = url .. "-L" .. line_end
		end
	end
	vim.ui.open(url)
end

return M
