-- Markdown writing aids: task toggles, table mode, image paste and the Fcitx
-- mode follower. Fcitx is replaced by a recorder; no daemon is contacted.
local ime = require("mayon.features.ime")
local state, calls = "1", {}
ime.remote = function(args)
	local flag = args and args[1]
	calls[#calls + 1] = flag or "query"
	if flag == "-c" then
		state = "1"
	elseif flag == "-o" then
		state = "2"
	end
	return state
end
ime.attach()

local function feed(keys)
	vim.api.nvim_feedkeys(vim.keycode(keys), "mtx", false)
end

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
vim.cmd.edit(dir .. "/notes.md")
assert(vim.bo.filetype == "markdown")
local note = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "- [ ] a", "- b", "c" })

-- Task toggles: count, list item promotion and Enter continuation.
vim.api.nvim_win_set_cursor(0, { 1, 0 })
feed("3,x")
assert(
	vim.deep_equal(vim.api.nvim_buf_get_lines(0, 0, -1, false), { "- [x] a", "- [ ] b", "- [ ] c" }),
	vim.inspect(vim.api.nvim_buf_get_lines(0, 0, -1, false))
)
feed("GA<CR>next<Esc>")
assert(
	vim.api.nvim_buf_get_lines(0, 3, 4, false)[1] == "- [ ] next",
	vim.inspect(vim.api.nvim_buf_get_lines(0, 0, -1, false))
)

-- Prose: Rime active on leave is switched off, then restored on re-entry.
calls, state = {}, "2"
feed("A<Esc>")
assert(state == "1" and vim.b.mayon_ime_active == true, vim.inspect(calls))
feed("A<Esc>")
assert(vim.tbl_contains(calls, "-o"), "prose buffer did not restore Rime: " .. vim.inspect(calls))

-- Code: switched off on leave, never restored on entry.
vim.cmd.enew()
vim.bo.filetype = "lua"
calls, state = {}, "2"
feed("ix<Esc>")
assert(state == "1", "code buffer left Rime active")
feed("a<Esc>")
assert(not vim.tbl_contains(calls, "-o"), "code buffer restored Rime: " .. vim.inspect(calls))
vim.cmd("bwipeout!")

-- Plugins load from the Markdown buffer and expose their entry points.
vim.api.nvim_set_current_buf(note)
assert(vim.fn.maparg(",p", "n") ~= "", "image paste key missing")
assert(vim.fn.exists(":TableModeToggle") == 2, "table mode was not loaded for Markdown")
assert(vim.g.table_mode_corner == "|")
assert(vim.fn.maparg(",tm", "n") ~= "", "table mode toggle key missing")
assert(vim.fn.maparg("<leader>tm", "n") == "", "table mode took the terminal leader group")
require("lz.n").trigger_load("img-clip.nvim")
assert(vim.fn.exists(":PasteImage") == 2 and not vim.g.mayon_load_error, vim.g.mayon_load_error)

vim.cmd("bwipeout!")
vim.fn.delete(dir, "rf")
assert(vim.v.errmsg == "", vim.v.errmsg)
print("Markdown tasks, table mode, image paste and IME follower passed")
