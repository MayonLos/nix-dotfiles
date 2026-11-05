-- Manual-only Aerial outline. Nothing opens on its own: the user toggles it
-- with <leader>o / <leader>co / Alt-7, and Aerial's own window owns the rest.
local M = {}

local function aerial()
	return require("aerial")
end

local function normalize_bufnr(bufnr)
	return (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
end

local function aerial_win(tabpage)
	tabpage = tabpage or vim.api.nvim_get_current_tabpage()
	if not vim.api.nvim_tabpage_is_valid(tabpage) then
		return nil
	end
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
		if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "aerial" then
			return win
		end
	end
end

-- Install the narrow blue rail on any Aerial window Aerial itself creates.
local function style_window(win)
	vim.wo[win].signcolumn = "no"
	vim.wo[win].number = true
	vim.wo[win].numberwidth = 1
	vim.wo[win].relativenumber = false
	vim.wo[win].winfixwidth = true
	vim.wo[win].statuscolumn = "%!v:lua.require'mayon.ui.outline'.statuscolumn()"
end

function M.is_supported(bufnr)
	bufnr = normalize_bufnr(bufnr)
	if not require("mayon.util").is_file_document(bufnr) then
		return false
	end
	local ok, status = pcall(function()
		return require("aerial.backends").get_status(bufnr)
	end)
	if not ok then
		return false
	end
	for _, backend in ipairs(status) do
		if backend.supported then
			return true
		end
	end
	return false
end

function M.is_open(tabpage)
	return aerial_win(tabpage) ~= nil
end

-- The tab's document window: the current one when it is a document, else the
-- first document window in the tab (explorer/terminal focus still works).
local function document_win()
	local util = require("mayon.util")
	local current = vim.api.nvim_get_current_win()
	if util.is_document_win(current) then
		return current
	end
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if util.is_document_win(win) then
			return win
		end
	end
end

function M.toggle()
	-- Closing takes precedence regardless of buffer kind, so a stale outline
	-- beside a tool buffer can still be dismissed.
	if M.is_open() then
		pcall(aerial().close)
		return false
	end
	local target = document_win()
	if not target or not M.is_supported(vim.api.nvim_win_get_buf(target)) then
		vim.notify("当前文件没有可用的符号大纲", vim.log.levels.INFO, { title = "Outline" })
		return false
	end
	-- Aerial opens for the target window's buffer; focus stays where it is.
	vim.api.nvim_win_call(target, function()
		aerial().open({ direction = "right", focus = false })
	end)
	local win = aerial_win()
	if win then
		style_window(win)
	end
	return win ~= nil
end

-- Aerial already keeps its cursor on the nearest symbol as source cursors move.
-- Add the narrow blue rail in its own statuscolumn while its line highlight
-- supplies the quiet selection background.
function M.statuscolumn()
	local win = tonumber(vim.g.statusline_winid) or vim.api.nvim_get_current_win()
	local ok, cursor = pcall(vim.api.nvim_win_get_cursor, win)
	if ok and cursor[1] == vim.v.lnum then
		return "%#MayonOutlineRail#▏%*"
	end
	return " "
end

-- Aerial sets b:source_buffer before it shows the buffer in a window, so this
-- also styles windows opened by Aerial's own commands (not only our toggle).
local function is_aerial_buf(buf)
	return vim.bo[buf].filetype == "aerial" or vim.b[buf].source_buffer ~= nil
end

function M.setup()
	if M._ready then
		return
	end
	M._ready = true
	vim.keymap.set("n", "<leader>o", M.toggle, { desc = "Toggle Symbol Outline", silent = true })
	local group = vim.api.nvim_create_augroup("MayonOutline", { clear = true })
	vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
		group = group,
		callback = function()
			local win = vim.api.nvim_get_current_win()
			if is_aerial_buf(vim.api.nvim_win_get_buf(win)) then
				-- Aerial finishes setting its window options right after the
				-- buffer enters, so restyle on the next tick to keep ours.
				vim.schedule(function()
					if vim.api.nvim_win_is_valid(win) then
						style_window(win)
					end
				end)
			end
		end,
	})
	-- :q in the last real window beside the outline would otherwise leave the
	-- outline alone and keep Neovim running. Close it first; the quitting window
	-- is still open, so this never hits E444 even in the last tab.
	vim.api.nvim_create_autocmd("QuitPre", {
		group = group,
		callback = function()
			local current = vim.api.nvim_get_current_win()
			local outline = aerial_win()
			if not outline or outline == current or vim.api.nvim_win_get_config(current).relative ~= "" then
				return
			end
			for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
				if
					win ~= current
					and win ~= outline
					and vim.api.nvim_win_get_config(win).relative == ""
					and not is_aerial_buf(vim.api.nvim_win_get_buf(win))
				then
					return
				end
			end
			pcall(vim.api.nvim_win_close, outline, true)
		end,
	})
	return M
end

return M
