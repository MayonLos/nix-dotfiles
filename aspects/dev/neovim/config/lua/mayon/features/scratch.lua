local M = {}
local api, uv = vim.api, vim.uv

local function scratch_dir()
	return vim.fn.stdpath("data") .. "/mayon-scratch"
end

local function notify(message, level)
	vim.notify(message, level, { title = "Scratch" })
end

local function is_scratch_buffer(buf)
	local name = api.nvim_buf_get_name(buf)
	local prefix = vim.fs.normalize(scratch_dir()) .. "/"
	return name:sub(1, #prefix) == prefix
end

function M.setup()
	local scratch_group = api.nvim_create_augroup("MayonScratchPersistence", { clear = true })
	-- Persist only scratch buffers, and only when the scratch buffer itself is
	-- the one being left. No per-buffer decision for unrelated BufLeave events.
	api.nvim_create_autocmd("BufLeave", {
		group = scratch_group,
		callback = function(args)
			local buf = args.buf
			if not is_scratch_buffer(buf) or not vim.bo[buf].modified then
				return
			end
			pcall(api.nvim_buf_call, buf, function()
				vim.cmd("silent write")
			end)
		end,
	})
	api.nvim_create_autocmd("VimLeavePre", {
		group = scratch_group,
		callback = function()
			for _, buf in ipairs(api.nvim_list_bufs()) do
				if is_scratch_buffer(buf) and vim.bo[buf].modified then
					pcall(api.nvim_buf_call, buf, function()
						vim.cmd("silent write")
					end)
				end
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

return M
