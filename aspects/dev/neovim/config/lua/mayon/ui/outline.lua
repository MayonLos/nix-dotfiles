-- Right-hand Aerial outline with per-tab automatic and manual state.
local M = {}

local manual_closed = {}
local last_document = {}
local aerial_windows = {}
local managed_closes = {}
local group
local reconcile_scheduled = false
local pending_reconciles = {}
local tab

local function normalize_bufnr(bufnr)
	return (bufnr == nil or bufnr == 0) and vim.api.nvim_get_current_buf() or bufnr
end

local function schedule_reconcile(bufnr, tabpage)
	tabpage = tabpage or tab()
	if not vim.api.nvim_tabpage_is_valid(tabpage) then
		return
	end
	pending_reconciles[tabpage] = bufnr or false
	if reconcile_scheduled then
		return
	end
	reconcile_scheduled = true
	vim.schedule(function()
		reconcile_scheduled = false
		local pending = pending_reconciles
		pending_reconciles = {}
		for target_tab, target_buf in pairs(pending) do
			if vim.api.nvim_tabpage_is_valid(target_tab) then
				M.reconcile(target_buf ~= false and target_buf or nil, target_tab)
			end
		end
	end)
end

local panel_filetypes = {
	aerial = true,
	["aerial-nav"] = true,
	oil = true,
	terminal = true,
	dashboard = true,
	alpha = true,
	starter = true,
	checkhealth = true,
	qf = true,
	quickfix = true,
	help = true,
	man = true,
	grug_far = true,
}

local unsupported_filetypes = vim.tbl_extend("force", vim.deepcopy(panel_filetypes), {
	snacks_dashboard = true,
	text = true,
})

tab = function()
	return vim.api.nvim_get_current_tabpage()
end

local function aerial()
	return require("aerial")
end

local function aerial_win(tabpage)
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage or tab())) do
		if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "aerial" then
			return win
		end
	end
end

local function style_window(win, tabpage)
	aerial_windows[win] = tabpage
	vim.wo[win].statuscolumn = "%!v:lua.require'mayon.ui.outline'.statuscolumn()"
	vim.wo[win].signcolumn = "no"
	vim.wo[win].number = true
	vim.wo[win].numberwidth = 1
	vim.wo[win].relativenumber = false
	vim.wo[win].winfixwidth = true
end

local function source_buffer(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end
	local name = vim.api.nvim_buf_get_name(bufnr)
	local buftype = vim.bo[bufnr].buftype
	local filetype = vim.bo[bufnr].filetype
	return name ~= "" and buftype == "" and filetype ~= "" and not unsupported_filetypes[filetype]
end

local function is_document_buffer(bufnr)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end
	local name = vim.api.nvim_buf_get_name(bufnr)
	local buftype = vim.bo[bufnr].buftype
	local filetype = vim.bo[bufnr].filetype
	return name ~= ""
		and buftype == ""
		and filetype ~= ""
		and not panel_filetypes[filetype]
		and not filetype:match("^snacks_")
end

local function document_buffer(tabpage)
	tabpage = tabpage or tab()
	local current_win = vim.api.nvim_tabpage_get_win(tabpage)
	local current = vim.api.nvim_win_get_buf(current_win)
	local ft = vim.bo[current].filetype
	if vim.bo[current].buftype == "terminal" or ft == "terminal" or ft == "snacks_dashboard" then
		return nil
	end
	if is_document_buffer(current) then
		return current
	end
	local remembered = last_document[tabpage]
	if remembered and vim.api.nvim_buf_is_valid(remembered) then
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
			if vim.api.nvim_win_get_buf(win) == remembered then
				return remembered
			end
		end
	end
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
		local bufnr = vim.api.nvim_win_get_buf(win)
		if is_document_buffer(bufnr) then
			return bufnr
		end
	end
end

local function backend_status(bufnr)
	local ok, status = pcall(function()
		return require("aerial.backends").get_status(bufnr)
	end)
	if not ok then
		return {}
	end
	return status
end

function M.is_supported(bufnr)
	bufnr = normalize_bufnr(bufnr)
	if not source_buffer(bufnr) then
		return false
	end
	for _, backend in ipairs(backend_status(bufnr)) do
		if backend.supported then
			return true
		end
	end
	return false
end

local function symbols_available(bufnr)
	if not M.is_supported(bufnr) then
		return false
	end
	return aerial().num_symbols(bufnr) > 0
end

local function wide_enough()
	return vim.o.columns >= 120
end

local function open_for(tabpage, bufnr, focus)
	if not vim.api.nvim_tabpage_is_valid(tabpage) then
		return false
	end
	local wins = vim.api.nvim_tabpage_list_wins(tabpage)
	local current = vim.api.nvim_tabpage_get_win(tabpage)
	local win
	for _, candidate in ipairs(wins) do
		if vim.api.nvim_win_get_buf(candidate) == bufnr then
			win = win or candidate
			if candidate == current then
				win = current
				break
			end
		end
	end
	if not win then
		return false
	end
	-- Run in the source window without changing the user's current tab/window.
	vim.api.nvim_win_call(win, function()
		aerial().open({ direction = "right", focus = focus == true })
	end)
	local opened = aerial_win(tabpage)
	if opened then
		style_window(opened, tabpage)
	end
	return opened ~= nil
end

local function has_other_window(tabpage, ...)
	local excluded = { ... }
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
		if vim.api.nvim_win_get_config(win).relative == "" and not vim.tbl_contains(excluded, win) then
			return true
		end
	end
	return false
end

local function close_in(tabpage)
	local win = aerial_win(tabpage)
	if not win then
		return false
	end
	-- Neovim refuses to close the last window of the last tab (E444).
	if #vim.api.nvim_list_tabpages() == 1 and not has_other_window(tabpage, win) then
		return false
	end
	managed_closes[win] = true
	vim.api.nvim_win_close(win, true)
	return true
end

-- Called by Aerial after a symbol provider has returned the first symbol set.
-- It avoids showing an empty sidebar while an LSP request is pending.
function M.on_symbols(bufnr)
	-- Ignore late updates for a different/background document. The scheduled
	-- callback runs after Aerial commits its new symbol list, including empty.
	if bufnr == document_buffer() then
		schedule_reconcile(bufnr)
	end
end

M.on_first_symbols = M.on_symbols

function M.should_open(bufnr)
	bufnr = normalize_bufnr(bufnr)
	if not wide_enough() or not source_buffer(bufnr) then
		return false
	end
	if manual_closed[tab()] or not symbols_available(bufnr) then
		return false
	end
	return true
end

function M.is_open(tabpage)
	return aerial_win(tabpage or tab()) ~= nil
end

function M.state(tabpage)
	tabpage = tabpage or tab()
	return {
		open = M.is_open(tabpage),
		manual_closed = manual_closed[tabpage] == true,
		wide = vim.o.columns >= 120,
	}
end

function M.reconcile(bufnr, tabpage)
	tabpage = tabpage or tab()
	if not vim.api.nvim_tabpage_is_valid(tabpage) then
		return false
	end
	if bufnr == nil then
		bufnr = document_buffer(tabpage)
	else
		bufnr = normalize_bufnr(bufnr)
	end
	local is_open = M.is_open(tabpage)
	local supported = bufnr ~= nil and M.is_supported(bufnr)
	if supported then
		-- Attach/request symbols on the initial buffer too; BufEnter may have
		-- happened before the lazy plugin lifecycle ran.
		pcall(require("aerial.backends").get, bufnr)
	end
	local can_show = wide_enough() and supported and symbols_available(bufnr)

	if is_open and not can_show then
		close_in(tabpage)
		return false
	end
	if is_open and can_show then
		local outline_win = aerial_win(tabpage)
		local bound_buf = vim.b[vim.api.nvim_win_get_buf(outline_win)].source_buffer
		local current_win = vim.api.nvim_tabpage_get_win(tabpage)
		local focus_is_source = vim.api.nvim_win_get_buf(current_win) == bufnr
		local different_window = focus_is_source and vim.w[outline_win].source_win ~= current_win
		if bound_buf ~= bufnr or different_window then
			close_in(tabpage)
			return open_for(tabpage, bufnr, false)
		end
	end
	if is_open or not can_show or manual_closed[tabpage] then
		return is_open
	end
	return open_for(tabpage, bufnr, false)
end

function M.toggle()
	local tabpage = tab()
	local bufnr = document_buffer(tabpage)
	local win = aerial_win(tabpage)
	if win then
		manual_closed[tabpage] = true
		close_in(tabpage)
		return false
	end
	if not bufnr or not M.is_supported(bufnr) then
		vim.notify("当前文件没有可用的符号大纲", vim.log.levels.INFO, { title = "符号大纲" })
		return false
	end
	manual_closed[tabpage] = false
	return M.reconcile(bufnr)
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

local function remember_aerial_window(tabpage)
	tabpage = tabpage or tab()
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
		if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "aerial" then
			style_window(win, tabpage)
		end
	end
end

function M.setup()
	if M._ready then
		return
	end
	M._ready = true
	group = vim.api.nvim_create_augroup("MayonOutline", { clear = true })

	vim.keymap.set("n", "<leader>o", M.toggle, { desc = "Toggle Symbol Outline", silent = true })

	vim.api.nvim_create_autocmd("WinNew", {
		group = group,
		callback = function()
			local tabpage = tab()
			vim.schedule(function()
				if vim.api.nvim_tabpage_is_valid(tabpage) then
					remember_aerial_window(tabpage)
				end
			end)
		end,
	})
	-- Quitting the last source window must also end the outline, or :q would
	-- leave the sidebar alone in the tab instead of exiting.
	vim.api.nvim_create_autocmd("QuitPre", {
		group = group,
		callback = function()
			local tabpage = tab()
			local current = vim.api.nvim_get_current_win()
			local outline = aerial_win(tabpage)
			if
				outline
				and outline ~= current
				and vim.api.nvim_win_get_config(current).relative == ""
				and not has_other_window(tabpage, outline, current)
			then
				close_in(tabpage)
			end
		end,
	})
	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		callback = function(event)
			local win = tonumber(event.match)
			local tabpage = win and aerial_windows[win]
			if not tabpage then
				return
			end
			aerial_windows[win] = nil
			if managed_closes[win] then
				managed_closes[win] = nil
			elseif vim.api.nvim_tabpage_is_valid(tabpage) then
				-- q, :AerialClose, and other user initiated closes stay closed
				-- until the user explicitly toggles the outline again.
				manual_closed[tabpage] = true
			end
		end,
	})
	vim.api.nvim_create_autocmd({
		"BufEnter",
		"WinEnter",
		"BufWinEnter",
		"FileType",
		"BufReadPost",
		"TabEnter",
		"WinResized",
		"VimResized",
		"LspAttach",
		"LspDetach",
		"TextChanged",
		"TextChangedI",
	}, {
		group = group,
		callback = function()
			local current = vim.api.nvim_get_current_buf()
			if is_document_buffer(current) then
				last_document[tab()] = current
			end
			local tabpage = tab()
			vim.schedule(function()
				if vim.api.nvim_tabpage_is_valid(tabpage) then
					remember_aerial_window(tabpage)
					schedule_reconcile(document_buffer(tabpage), tabpage)
				end
			end)
		end,
	})
	vim.api.nvim_create_autocmd("TabClosed", {
		group = group,
		callback = function()
			vim.schedule(function()
				for tabpage in pairs(manual_closed) do
					if not vim.api.nvim_tabpage_is_valid(tabpage) then
						manual_closed[tabpage] = nil
						last_document[tabpage] = nil
					end
				end
			end)
		end,
	})
	schedule_reconcile(vim.api.nvim_get_current_buf(), tab())
	return M
end

return M
