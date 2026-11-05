-- The manual outline is tab-local and safe around window/tab teardown: no
-- reconcile state machine, no automatic open, and closing never raises E444.
local outline = require("mayon.ui.outline")
outline.setup()
require("lz.n").trigger_load("aerial.nvim")
vim.o.columns, vim.o.lines = 180, 50

local path = vim.fn.tempname() .. ".lua"
vim.fn.writefile({ "local function outline_race_fixture() return true end" }, path)
vim.cmd.edit(vim.fn.fnameescape(path))
local source_win = vim.api.nvim_get_current_win()

-- Symbols must arrive before the outline can be toggled on.
local outline_win = nil
assert(
	vim.wait(3000, function()
		outline.toggle()
		outline_win = (function()
			for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
				if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "aerial" then
					return win
				end
			end
		end)()
		return outline_win ~= nil
	end, 25),
	"manual toggle on a Lua document should open the outline"
)
assert(vim.wo[outline_win].statuscolumn:find("outline", 1, true), "outline must install its rail")

-- A second toggle closes it.
outline.toggle()
assert(
	vim.wait(500, function()
		return not outline.is_open()
	end),
	"toggle should close the outline"
)

-- The default is closed: reopening a fresh tab never auto-opens.
vim.cmd.tabnew()
local second_tab = vim.api.nvim_get_current_tabpage()
assert(not outline.is_open(second_tab), "a fresh tab must not auto-open the outline")
vim.cmd.tabprevious()

-- Closing the last non-outline window beside an open outline must not raise
-- E444; Aerial's close is safe and leaves Neovim usable.
vim.o.columns = 100
outline.toggle()
assert(
	vim.wait(500, function()
		return outline.is_open()
	end),
	"narrow manual open still works"
)
vim.cmd("only") -- collapses to the outline+source; no error
assert(vim.v.errmsg == "", "window teardown raised an error")

print("Manual outline toggle, tab locality and teardown safety passed")

local function find_outline()
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "aerial" then
			return win
		end
	end
end

-- Toggling from a tool window targets the tab's document window and keeps
-- focus on the tool window.
vim.o.columns = 180
if outline.is_open() then
	outline.toggle()
end
vim.api.nvim_set_current_win(source_win)
vim.cmd("topleft 30vsplit")
local tool_win = vim.api.nvim_get_current_win()
local tool_buf = vim.api.nvim_create_buf(false, true)
vim.bo[tool_buf].filetype = "snacks_picker_list"
vim.api.nvim_win_set_buf(tool_win, tool_buf)
assert(outline.toggle(), "toggle from a tool window should open the document's outline")
assert(vim.api.nvim_get_current_win() == tool_win, "toggle must keep focus in the tool window")
local opened = assert(find_outline())
local source_buf = vim.api.nvim_win_get_buf(source_win)
assert(
	vim.b[vim.api.nvim_win_get_buf(opened)].source_buffer == source_buf
		or require("aerial.util").get_source_buffer(vim.api.nvim_win_get_buf(opened)) == source_buf,
	"outline must belong to the document, not the tool buffer"
)
vim.api.nvim_win_close(tool_win, true)

-- :q in the last source window beside the outline closes the outline first,
-- so the quit closes the tab (or exits Neovim) instead of leaving it alone.
vim.cmd.tabnew()
vim.cmd.edit(vim.fn.fnameescape(path))
local quit_tab = vim.api.nvim_get_current_tabpage()
assert(
	vim.wait(3000, function()
		return outline.toggle() or outline.is_open()
	end, 25),
	"outline should open in the quit tab"
)
local quit_outline = assert(find_outline())
vim.cmd("quit")
assert(not vim.api.nvim_win_is_valid(quit_outline), "QuitPre must close the outline beside the last source")
assert(not vim.api.nvim_tabpage_is_valid(quit_tab), ":q on the last source must close its tab")
assert(vim.v.errmsg == "", "quitting beside the outline raised an error")

-- A remaining split keeps the outline: only the last real window triggers it.
vim.cmd.tabnew()
vim.cmd.edit(vim.fn.fnameescape(path))
assert(
	vim.wait(3000, function()
		return outline.toggle() or outline.is_open()
	end, 25),
	"outline should open beside a split"
)
vim.cmd.split()
vim.cmd("quit")
assert(outline.is_open(), "QuitPre must keep the outline while another source window remains")
print("Outline toggle target and quit handling passed")
