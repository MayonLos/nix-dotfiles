-- Tool windows are opened only by explicit actions; the editor needs no framing splits.
local M = {}

function M.in_cmdwin()
	return vim.fn.getcmdwintype() ~= ""
end

function M.editor()
	local util = require("mayon.util")
	local current = vim.api.nvim_get_current_win()
	if util.is_document_win(current) then
		return current
	end
	for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if util.is_document_win(w) then
			return w
		end
	end
end

function M.action(name)
	local S = require("snacks")
	local editor = M.editor()
	if editor then
		vim.api.nvim_set_current_win(editor)
	end
	if name == "project" then
		S.explorer({ focus = "list" })
	elseif name == "commit" then
		vim.cmd.Neogit()
	elseif name == "structure" then
		require("mayon.ui.outline").toggle()
	elseif name == "marks" then
		S.picker.marks()
	elseif name == "terminal" then
		S.terminal(nil, { win = { position = "bottom", height = 0.25 } })
	elseif name == "problems" then
		vim.cmd("Trouble diagnostics toggle")
	elseif name == "history" then
		vim.cmd("CodeDiff history")
	elseif name == "ai" then
		vim.cmd("CodeCompanionChat Toggle")
	elseif name == "notifications" then
		S.notifier.show_history()
	elseif name == "tasks" then
		require("mayon.features.tasks").pick()
	end
end

function M.setup() end
return M
