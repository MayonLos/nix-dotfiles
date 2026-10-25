local M = {}
local labels = { "Terminal", "Problems", "Git", "Tasks" }
function M.click(id)
	vim.schedule(function()
		require("mayon.ui.workspace").action(({ "terminal", "problems", "commit", "tasks" })[id])
	end)
end
function M.render()
	local win = tonumber(vim.g.statusline_winid) or 0
	local buf = vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) or 0
	local ft = vim.bo[buf].filetype
	local active = (ft == "trouble" or ft == "qf") and 2 or ft:match("git") and 3 or 1
	local parts = { " " }
	for i, label in ipairs(labels) do
		parts[#parts + 1] = (i == active and "%#TabLineSel#" or "%#TabLine#")
			.. "%"
			.. i
			.. "@v:lua.MayonBottomClick@ "
			.. label
			.. " %X  "
	end
	return table.concat(parts)
		.. "%=%#MayonPanelTitle# "
		.. (ft == "qf" and "Quickfix" or ft == "trouble" and "Diagnostics" or "Terminal")
		.. " · Workspace "
end
function M.setup()
	_G.MayonBottomClick = M.click
end
return M
