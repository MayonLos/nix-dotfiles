-- Shared editor predicates and window helpers. Every domain uses these
-- instead of keeping its own copy of "is this a document" or winhighlight
-- string handling.
local M = {}

-- One border style for floats, menus, pickers and panels.
M.border = "rounded"

-- Below this width side panels give way to floats and stay closed.
M.wide_columns = 120

function M.wide()
	return vim.o.columns >= M.wide_columns
end

function M.palette()
	return require("mayon.generated").palette
end

-- Tool and panel buffers never count as documents, even when listed.
local tool_filetypes = {
	aerial = true,
	checkhealth = true,
	["grug-far"] = true,
	grug_far = true,
	help = true,
	helpft = true,
	man = true,
	oil = true,
	qf = true,
	quickfix = true,
	trouble = true,
}
local tool_prefixes = { "claudecode", "codecompanion", "neogit", "snacks" }

-- A listed buffer the user edits as text: a file, or an unnamed scratch
-- buffer, but no terminal, prompt, picker, sidebar or AI panel.
function M.is_document(buf)
	if not buf or not vim.api.nvim_buf_is_valid(buf) or not vim.bo[buf].buflisted then
		return false
	end
	local buftype = vim.bo[buf].buftype
	if buftype ~= "" and buftype ~= "acwrite" then
		return false
	end
	local filetype = vim.bo[buf].filetype:lower()
	if tool_filetypes[filetype] then
		return false
	end
	for _, prefix in ipairs(tool_prefixes) do
		if filetype:sub(1, #prefix) == prefix then
			return false
		end
	end
	return true
end

-- A document backed by a path on disk (what sessions and file actions need).
function M.is_file_document(buf)
	return M.is_document(buf) and vim.api.nvim_buf_get_name(buf) ~= ""
end

-- A normal (non-floating) window that shows a document.
function M.is_document_win(win)
	return win ~= nil
		and vim.api.nvim_win_is_valid(win)
		and vim.api.nvim_win_get_config(win).relative == ""
		and M.is_document(vim.api.nvim_win_get_buf(win))
end

-- Parse a 'winhighlight' value into { from = to }.
function M.winhl_parse(value)
	local map = {}
	for pair in (value or ""):gmatch("[^,]+") do
		local from, to = pair:match("^%s*([^:]+):(.-)%s*$")
		if from and to ~= "" then
			map[from] = to
		end
	end
	return map
end

-- Serialize { from = to } in a stable order.
function M.winhl_string(map)
	local keys = vim.tbl_keys(map)
	table.sort(keys)
	local parts = {}
	for _, from in ipairs(keys) do
		parts[#parts + 1] = from .. ":" .. map[from]
	end
	return table.concat(parts, ",")
end

-- Merge highlight links into a window. A `false` value removes that link;
-- links the caller does not mention are kept.
function M.winhl(win, links)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return
	end
	local map = M.winhl_parse(vim.wo[win].winhighlight)
	for from, to in pairs(links) do
		map[from] = to or nil
	end
	vim.wo[win].winhighlight = M.winhl_string(map)
end

return M
