-- A delayed BufEnter reconciliation must retain the tab that raised it.
-- Switching tabs before scheduled callbacks run used to send the first tab's
-- buffer to M.reconcile while that function implicitly operated on tab 2.
local outline = require("mayon.ui.outline")
outline.setup()
vim.wait(50)

local first_tab = vim.api.nvim_get_current_tabpage()
local first_window = vim.api.nvim_get_current_win()
local path = vim.fn.tempname() .. ".lua"
vim.fn.writefile({ "local function outline_race_fixture() return true end" }, path)
local source = vim.fn.bufadd(path)
vim.fn.bufload(source)
vim.bo[source].filetype = "lua"
vim.api.nvim_win_set_buf(first_window, source)
vim.wait(30)

vim.cmd("tabnew")
local second_tab = vim.api.nvim_get_current_tabpage()
vim.wait(50)
assert(first_tab ~= second_tab, "fixture must use two distinct tabs")

local original_reconcile = outline.reconcile
local seen
outline.reconcile = function(bufnr, tabpage)
	if bufnr == source then
		seen = { bufnr = bufnr, tabpage = tabpage }
	end
	return false
end

vim.api.nvim_set_current_tabpage(first_tab)
vim.api.nvim_set_current_win(first_window)
vim.api.nvim_exec_autocmds("BufEnter", { buffer = source, modeline = false })
-- The autocmd schedules its work. Move away before either scheduled callback
-- executes so the test observes the same timing window as a rapid tab switch.
vim.api.nvim_set_current_tabpage(second_tab)
assert(
	vim.wait(1000, function()
		return seen ~= nil
	end, 5),
	"BufEnter should eventually reconcile the source buffer"
)
outline.reconcile = original_reconcile

assert(seen.bufnr == source, "reconciliation must retain the event's source buffer")
assert(seen.tabpage == first_tab, "reconciliation must retain the event's originating tab")
print("Outline cross-tab scheduled reconciliation passed")

-- A background reconciliation must retain that tab's selected source split,
-- even when the foreground tab displays the same buffer.
require("mayon.features.ai_completion").set("off")
require("lz.n").trigger_load("aerial.nvim")
vim.o.columns = 180
vim.o.lines = 50
vim.api.nvim_set_current_tabpage(first_tab)
vim.api.nvim_set_current_win(first_window)
vim.cmd.vsplit()
local selected_source = vim.api.nvim_get_current_win()
vim.api.nvim_win_set_buf(selected_source, source)
assert(
	vim.wait(3000, function()
		outline.reconcile(source, first_tab)
		return outline.is_open(first_tab)
	end, 25),
	"first tab outline did not acquire symbols"
)
local function outline_window(tabpage)
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
		if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "aerial" then
			return win
		end
	end
end
local first_outline = assert(outline_window(first_tab))
assert(vim.w[first_outline].source_win == selected_source, "outline did not bind selected source split")
vim.api.nvim_set_current_tabpage(second_tab)
vim.api.nvim_win_set_buf(0, source)
vim.wait(150)
outline.reconcile(source, first_tab)
first_outline = assert(outline_window(first_tab))
assert(vim.w[first_outline].source_win == selected_source, "background reconcile rebound the wrong source split")
assert(vim.api.nvim_get_current_tabpage() == second_tab, "background reconcile changed foreground tab")
print("Outline same-buffer background-tab source split passed")
