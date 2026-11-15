-- mini.ai textobjects (Tree-sitter f/i plus builtin a/q/g) and dial.nvim
-- increments, driven through real keys on real files.
local function feed(keys)
	vim.api.nvim_feedkeys(vim.keycode(keys), "mtx", false)
end
local function lines()
	return vim.api.nvim_buf_get_lines(0, 0, -1, false)
end

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local path = dir .. "/fixture.lua"
vim.fn.writefile({
	"local function f(a, b)",
	"\tif a then",
	'\t\treturn "x", b',
	"\tend",
	"end",
	"local enabled = true",
}, path)
vim.cmd.edit(path)
assert(package.loaded["mini.ai"], "mini.ai must load with the editing group")
vim.treesitter.start(0, "lua")

-- Tree-sitter conditional (ii) and function (af) keep their previous meaning.
vim.api.nvim_win_set_cursor(0, { 3, 2 })
feed("dii")
assert(lines()[2] == "\tif a then" and vim.trim(lines()[3]) == "" and lines()[4] == "\tend", vim.inspect(lines()))
feed("u")
-- Argument and quote objects. Like the old Tree-sitter query, the first
-- argument keeps the following space.
vim.api.nvim_win_set_cursor(0, { 1, 17 })
feed("daa")
assert(lines()[1] == "local function f( b)", vim.inspect(lines()))
vim.api.nvim_win_set_cursor(0, { 3, 2 })
feed("ciqy<Esc>")
assert(lines()[3] == '\t\treturn "y", b', vim.inspect(lines()))
-- Whole buffer object.
feed("yag")
assert(#vim.split(vim.fn.getreg('"'), "\n", { trimempty = true }) == #lines())
vim.api.nvim_win_set_cursor(0, { 1, 0 })
-- Charwise like the old Tree-sitter selection: the function's line stays empty.
feed("daf")
assert(vim.deep_equal(lines(), { "", "local enabled = true" }), vim.inspect(lines()))

-- dial: booleans, numbers, dates and Markdown headings.
vim.api.nvim_win_set_cursor(0, { 2, 16 })
feed("<C-a>")
assert(lines()[2] == "local enabled = false", vim.inspect(lines()))
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "x = -1", "2026-11-08", "a && b" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
feed("2<C-a>")
assert(lines()[1] == "x = 1", vim.inspect(lines()))
vim.api.nvim_win_set_cursor(0, { 2, 9 })
feed("<C-a>")
assert(lines()[2] == "2026-11-09", vim.inspect(lines()))
vim.api.nvim_win_set_cursor(0, { 3, 2 })
feed("<C-a>")
assert(lines()[3] == "a || b", vim.inspect(lines()))
vim.cmd("bwipeout!")

vim.fn.writefile({ "## Title" }, dir .. "/h.md")
vim.cmd.edit(dir .. "/h.md")
feed("<C-a>")
assert(lines()[1] == "### Title", vim.inspect(lines()))
vim.cmd("bwipeout!")

vim.fn.delete(dir, "rf")
assert(not vim.g.mayon_load_error, vim.g.mayon_load_error)
assert(vim.v.errmsg == "", vim.v.errmsg)
print("mini.ai textobjects and dial increments passed")
