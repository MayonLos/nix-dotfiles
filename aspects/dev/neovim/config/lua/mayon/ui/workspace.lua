-- Tool windows are opened only by explicit actions; the editor needs no framing splits.
local M = {}
local function buffer_labels(buffers)
	local paths, counts, suffix_counts = {}, {}, {}
	for _, buf in ipairs(buffers) do
		local name = vim.api.nvim_buf_get_name(buf)
		local parts = name == "" and {} or vim.split(vim.fn.fnamemodify(name, ":~:."), "/", { trimempty = true })
		paths[buf] = parts
		local base = parts[#parts] or "[No Name]"
		counts[base] = (counts[base] or 0) + 1
	end
	for _, parts in pairs(paths) do
		local suffix = ""
		for i = #parts, 1, -1 do
			suffix = suffix == "" and parts[i] or (parts[i] .. "/" .. suffix)
			suffix_counts[suffix] = (suffix_counts[suffix] or 0) + 1
		end
	end
	local labels = {}
	for _, buf in ipairs(buffers) do
		local parts = paths[buf]
		local base = parts[#parts] or "[No Name]"
		local label = base
		if counts[base] > 1 then
			if #parts == 0 then
				label = base .. " #" .. buf
			else
				for i = #parts - 1, 1, -1 do
					label = parts[i] .. "/" .. label
					if suffix_counts[label] == 1 then
						break
					end
				end
				if suffix_counts[label] ~= 1 then
					label = label .. " #" .. buf
				end
			end
		end
		labels[buf] = label
	end
	return labels
end
M.buffer_labels = buffer_labels
local function document(win)
	if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_config(win).relative ~= "" then
		return false
	end
	local b = vim.api.nvim_win_get_buf(win)
	return vim.bo[b].buftype == "" and vim.bo[b].filetype ~= "" and vim.bo[b].filetype ~= "snacks_dashboard"
end
function M.in_cmdwin()
	return vim.fn.getcmdwintype() ~= ""
end
function M.editor()
	local current = vim.api.nvim_get_current_win()
	if document(current) then
		return current
	end
	for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if document(w) then
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
		require("lz.n").trigger_load("aerial.nvim")
		require("aerial").toggle({ focus = true })
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
