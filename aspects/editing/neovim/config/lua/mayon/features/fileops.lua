-- Guard file operations that Snacks delegates to the editor configuration.
local M = {}

local api = vim.api
local uv = vim.uv or vim.loop

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

local function file_uri(path)
	return vim.uri_from_fname(path)
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
		local function reject_write(message)
			vim.bo[buf].modified = true
			notify(message, vim.log.levels.ERROR)
			error(message, 0)
		end
		id = api.nvim_create_autocmd("BufWriteCmd", {
			buffer = buf,
			nested = true,
			desc = "Safely write a buffer after native file rename",
			callback = function()
				if api.nvim_buf_get_name(buf) ~= path then
					reject_write("Buffer path changed again; rename it through the file operation before saving.")
					return
				end
				if vim.v.cmdbang ~= 1 and stat_fingerprint(path) ~= expected then
					reject_write("File changed outside Neovim; buffer kept. Use :write! only to override deliberately.")
					return
				end
				api.nvim_del_autocmd(id)
				vim.b[buf].mayon_rename_write_autocmd = nil
				vim.bo[buf].buftype = buftype
				local ok, err = pcall(api.nvim_buf_call, buf, function()
					-- Let Neovim run BufWritePre and BufWritePost once as part of
					-- the real write. Manually dispatching these events from inside
					-- BufWriteCmd skips non-nested user autocmds.
					vim.cmd("write!")
				end)
				if not ok then
					vim.bo[buf].buftype = "acwrite"
					register()
					reject_write("Could not write renamed file: " .. tostring(err))
				else
					vim.b[buf].mayon_original_buftype = nil
				end
			end,
		})
		vim.b[buf].mayon_rename_write_autocmd = id
	end
	register()
end

local function buffers_for_path(old, renaming_directory)
	local buffers, clients = {}, {}
	for _, candidate in ipairs(api.nvim_list_bufs()) do
		if api.nvim_buf_is_valid(candidate) then
			local name = api.nvim_buf_get_name(candidate)
			if name ~= "" then
				name = normalize(name)
				if name == old or (renaming_directory and name:sub(1, #old + 1) == old .. "/") then
					buffers[#buffers + 1] = candidate
					for _, client in ipairs(vim.lsp.get_clients({ bufnr = candidate })) do
						clients[client.id] = client
					end
				end
			end
		end
	end
	return buffers, clients
end

local function buffer_conflict(target, old, renaming_directory)
	for _, candidate in ipairs(api.nvim_list_bufs()) do
		if api.nvim_buf_is_valid(candidate) then
			local name = api.nvim_buf_get_name(candidate)
			if name ~= "" then
				name = normalize(name)
				local belongs_to_source = name == old or (renaming_directory and name:sub(1, #old + 1) == old .. "/")
				if not belongs_to_source and (name == target or name:sub(1, #target + 1) == target .. "/") then
					return name
				end
			end
		end
	end
	return nil
end

local function rename_now(old, new)
	old, new = normalize(old), normalize(new)
	local renaming_directory = is_dir(old)
	if old == new then
		return false, "Source and target are the same"
	end
	if renaming_directory and (old == "/" or new:sub(1, #old + 1) == old .. "/") then
		return false, "Cannot move a directory into itself"
	end
	if not uv.fs_lstat(old) then
		return false, "Source does not exist: " .. old
	end
	if uv.fs_lstat(new) then
		return false, "Target already exists: " .. new
	end
	local conflicting_buffer = buffer_conflict(new, old, renaming_directory)
	if conflicting_buffer then
		return false, "Target is already open in a buffer: " .. conflicting_buffer
	end
	if not is_dir(vim.fs.dirname(new)) then
		return false, "Target parent directory does not exist"
	end
	local buffers, clients = buffers_for_path(old, renaming_directory)
	local changes = {}
	for _, client in pairs(clients) do
		if client:supports_method("workspace/willRenameFiles") then
			local response = client:request_sync("workspace/willRenameFiles", {
				files = { { oldUri = file_uri(old), newUri = file_uri(new) } },
			}, 1500, buffers[1] or 0)
			if response and response.result then
				changes[#changes + 1] = { client = client, edit = response.result }
			end
		end
	end
	local ok, err = uv.fs_rename(old, new)
	if not ok then
		return false, "Rename failed: " .. tostring(err)
	end
	for _, change in ipairs(changes) do
		vim.lsp.util.apply_workspace_edit(change.edit, change.client.offset_encoding)
	end
	for _, candidate in ipairs(buffers) do
		if api.nvim_buf_is_valid(candidate) then
			local candidate_name = normalize(api.nvim_buf_get_name(candidate))
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
	return true
end

function M.rename_file(opts)
	opts = opts or {}
	local from = opts.from or opts.file or api.nvim_buf_get_name(0)
	if from == "" then
		notify("Current buffer has no file", vim.log.levels.WARN)
		if opts.on_rename then
			opts.on_rename(opts.to, from, false)
		end
		return false
	end
	from = normalize(from)
	local function finish(to)
		if not to or to == "" then
			return false
		end
		local ok, err = rename_now(from, to)
		if not ok then
			notify(err, vim.log.levels.ERROR)
		elseif not opts.on_rename then
			notify("Renamed to " .. vim.fn.fnamemodify(normalize(to), ":~:.") .. " (buffer changes kept)")
		end
		if opts.on_rename then
			opts.on_rename(normalize(to), from, ok)
		end
		return ok
	end
	if opts.to then
		return finish(opts.to)
	end
	vim.ui.input({ prompt = "Rename to: ", default = from, completion = "file" }, function(input)
		if input and input ~= "" then
			finish(input)
		end
	end)
end

function M.trash(path, resolve)
	path = normalize(path)
	local directory = is_dir(path)
	for _, buf in ipairs(api.nvim_list_bufs()) do
		if api.nvim_buf_is_valid(buf) and vim.bo[buf].modified then
			local name = api.nvim_buf_get_name(buf)
			if name ~= "" then
				name = normalize(name)
				if name == path or (directory and name:sub(1, #path + 1) == path .. "/") then
					return false,
						"Unsaved buffer changes for " .. name .. "; save or close the buffer before moving it to trash"
				end
			end
		end
	end
	local executable = (resolve or vim.fn.exepath)("trash-put")
	if executable == "" then
		executable = (resolve or vim.fn.exepath)("trash")
	end
	if executable == "" then
		return false, "No trash command is installed; item was not deleted"
	end
	local result = vim.system({ executable, path }, { text = true }):wait()
	if result.code ~= 0 then
		return false, (result.stderr or "Trash command failed")
	end
	return true
end

function M.setup()
	local snacks = require("snacks")
	snacks.rename.rename_file = M.rename_file
	require("snacks.explorer.actions").trash = M.trash
end

return M
