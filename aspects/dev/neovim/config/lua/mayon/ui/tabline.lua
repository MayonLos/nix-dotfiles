-- Document identity is preserved while a picker or tool window has focus.
local M = {}
local active_documents = {}

local excluded_filetypes = {
	checkhealth = true,
	["grug-far"] = true,
	grug_far = true,
	oil = true,
	aerial = true,
	trouble = true,
	quickfix = true,
	qf = true,
	help = true,
	man = true,
	helpft = true,
}

local function is_document(buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) or not vim.bo[buf].buflisted then
		return false
	end
	local buftype = vim.bo[buf].buftype
	if buftype ~= "" and buftype ~= "acwrite" then
		return false
	end
	local filetype = vim.bo[buf].filetype:lower()
	if excluded_filetypes[filetype] then
		return false
	end
	for _, prefix in ipairs({ "neogit", "snacks", "codecompanion", "claudecode" }) do
		if filetype:sub(1, #prefix) == prefix then
			return false
		end
	end
	return true
end

-- Focus may move to a sidebar or prompt without changing the active document.
function M.active_buffer()
	local tab, buf = vim.api.nvim_get_current_tabpage(), vim.api.nvim_get_current_buf()
	if is_document(buf) then
		active_documents[tab] = buf
	elseif not is_document(active_documents[tab]) then
		active_documents[tab] = nil
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
			local visible = vim.api.nvim_win_get_buf(win)
			if is_document(visible) then
				active_documents[tab] = visible
				break
			end
		end
	end
	return active_documents[tab]
end

-- Presentation filtering never deletes a buffer or hides unsaved scratch work.
function M.buffers()
	local result = {}
	for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
		local buf = info.bufnr
		local empty = vim.api.nvim_buf_get_name(buf) == ""
			and vim.bo[buf].buftype == ""
			and not vim.bo[buf].modified
			and vim.api.nvim_buf_is_loaded(buf)
			and vim.api.nvim_buf_line_count(buf) == 1
			and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
		if is_document(buf) and not empty then
			result[#result + 1] = buf
		end
	end
	return result
end

function M.select(buf)
	if not is_document(buf) then
		return
	end
	local function document_window(win)
		return vim.api.nvim_win_get_config(win).relative == "" and is_document(vim.api.nvim_win_get_buf(win))
	end
	local win = vim.api.nvim_get_current_win()
	if not document_window(win) then
		win = nil
		for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if document_window(candidate) then
				win = candidate
				break
			end
		end
		if not win then
			vim.cmd("botright vnew")
			win = vim.api.nvim_get_current_win()
		end
	end
	vim.api.nvim_win_set_buf(win, buf)
	vim.api.nvim_set_current_win(win)
end

return M
