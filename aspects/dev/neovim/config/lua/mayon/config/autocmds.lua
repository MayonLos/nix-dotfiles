local M = {}

function M.setup()
	require("mayon.ui.terminal").setup()
	local group = vim.api.nvim_create_augroup("MayonCore", { clear = true })
	vim.api.nvim_create_autocmd("BufReadPost", {
		group = group,
		callback = function(args)
			local mark = vim.api.nvim_buf_get_mark(args.buf, '"')
			if mark[1] > 0 and mark[1] <= vim.api.nvim_buf_line_count(args.buf) then
				pcall(vim.api.nvim_win_set_cursor, 0, mark)
			end
		end,
	})
	-- Scratch/picker styles may change inherited window options. Reassert the
	-- editor cursor line when a normal document becomes the active view.
	vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
		group = group,
		callback = function(ev)
			if vim.bo[ev.buf].buftype == "" and vim.bo[ev.buf].filetype ~= "" and not vim.wo.diff then
				vim.wo.cursorline = true
				vim.wo.cursorlineopt = "both"
			end
		end,
	})
	-- Replace the binary read with the desktop PDF handler.
	vim.api.nvim_create_autocmd("BufReadCmd", {
		group = group,
		pattern = { "*.pdf", "*.PDF" },
		callback = function(args)
			local file = vim.fn.fnamemodify(args.file, ":p")
			local proc, err = vim.ui.open(file)
			if not proc then
				vim.notify("Cannot open " .. file .. ": " .. tostring(err), vim.log.levels.ERROR)
				return
			end
			vim.notify(vim.fs.basename(file), vim.log.levels.INFO, { title = "Opened externally" })
			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(args.buf) then
					vim.api.nvim_buf_delete(args.buf, { force = true })
				end
			end)
		end,
	})
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		callback = function(ev)
			vim.bo[ev.buf].spelllang = "en,cjk"
			vim.wo.spell = vim.tbl_contains({ "markdown", "gitcommit", "tex" }, ev.match)
		end,
	})
end

return M
