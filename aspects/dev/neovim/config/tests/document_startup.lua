-- Cold-start path: an argv file (or the :edit fallback used by standalone
-- runs) must start with the outline closed; only the manual toggle opens it.
vim.o.columns, vim.o.lines = 160, 48
vim.api.nvim_exec_autocmds("VimResized", {})
if vim.bo.filetype ~= "c" then
	local path = vim.fn.tempname() .. ".c"
	vim.fn.writefile({ "int main(void) { return 0; }" }, path)
	vim.cmd.edit(vim.fn.fnameescape(path))
end
local outline = require("mayon.ui.outline")
assert(vim.bo.filetype == "c", "cold-start fixture must be a C document")
require("mayon.ui.tabline").refresh()
assert(vim.o.showtabline == 2, "document must display its project header")

-- Startup never opens the outline on its own.
vim.wait(500)
assert(not outline.is_open(), "a document must not auto-open its outline")

-- A manual toggle still works before/around the first UI frame.
assert(
	vim.wait(5000, function()
		if not outline.is_open() then
			outline.toggle()
		end
		return outline.is_open()
	end, 25),
	"manual toggle must open the outline for a document"
)
local outline_win
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
	if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "aerial" then
		outline_win = win
	end
end
assert(
	outline_win and vim.wo[outline_win].statuscolumn:find("outline", 1, true),
	"outline must install its current-symbol rail"
)
outline.toggle()
assert(
	vim.wait(500, function()
		return not outline.is_open()
	end),
	"a second toggle must close the outline"
)
-- Icon overrides belong in devicons' persistent setup options.
local icons = require("mayon.ui.icons")
local _, group = icons.get("sample.h")
local blue = tonumber(require("mayon.generated").palette.blue:sub(2), 16)
assert(vim.api.nvim_get_hl(0, { name = group, link = false }).fg == blue, "header-file icon must use the blue accent")
vim.cmd.colorscheme("onedark")
vim.wait(50)
assert(vim.api.nvim_get_hl(0, { name = group, link = false }).fg == blue, "theme reload must preserve the blue devicon")
print("Argv-file outline stays closed, manual toggle and persistent icon colors passed")
