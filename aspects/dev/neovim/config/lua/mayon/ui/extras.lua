-- Window-local surfaces for built-in buffers and secondary plugin views.
local M = {}

function M.style(win, title)
	if not vim.api.nvim_win_is_valid(win) then
		return
	end
	vim.wo[win].winhighlight =
		"Normal:NormalFloat,NormalNC:NormalFloat,WinBar:MayonPanelTitle,WinSeparator:FloatBorder,CursorLine:PmenuSel"
	if title then
		vim.wo[win].winbar = "%#MayonPanelTitle# " .. title:gsub("%%", "%%%%") .. " %*"
	end
end

function M.setup()
	vim.api.nvim_create_autocmd("FileType", {
		group = vim.api.nvim_create_augroup("MayonSecondarySurfaces", { clear = true }),
		pattern = { "oil", "grug-far", "checkhealth", "help", "cmd", "msg", "pager", "dialog", "codediff-explorer" },
		callback = function(event)
			local ft = vim.bo[event.buf].filetype
			local titles = {
				oil = "OIL",
				["grug-far"] = "SEARCH · REPLACE",
				checkhealth = "HEALTH",
				["codediff-explorer"] = "GIT REVIEW",
				help = "HELP",
			}
			for _, win in ipairs(vim.fn.win_findbuf(event.buf)) do
				M.style(win, titles[ft])
			end
		end,
	})
end

return M
