local M = {}
local api, uv = vim.api, vim.uv
local function scratch_dir()
	return vim.fn.stdpath("data") .. "/mayon-scratch"
end
local function notify(message, level)
	vim.notify(message, level, { title = "Scratch" })
end

function M.setup()
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
	if vim.bo.filetype ~= "markdown" then
		vim.bo.filetype = "markdown"
	end
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

return M
