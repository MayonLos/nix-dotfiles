-- Opened as an argv file, before the first UI frame. Do not call Aerial's
-- num_symbols()/open APIs here: either would hide its second lazy-load layer.
vim.o.columns, vim.o.lines = 160, 48
vim.api.nvim_exec_autocmds("VimResized", {})
local outline = require("mayon.ui.outline")
assert(vim.bo.filetype == "c", "cold-start fixture must be a C argv file")
assert(
	vim.wait(5000, function()
		return outline.is_open()
	end, 20),
	"argv C file must open its outline automatically"
)
assert(vim.o.showtabline == 2, "argv document must display its project header")
local outline_win
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
	if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "aerial" then
		outline_win = win
	end
end
assert(
	outline_win and vim.wo[outline_win].statuscolumn:find("outline", 1, true),
	"cold outline must install its current-symbol rail"
)
-- Icon overrides belong in devicons' persistent setup options.
local icons = require("mayon.ui.icons")
local _, group = icons.get("sample.h")
local blue = tonumber(require("mayon.generated").palette.blue:sub(2), 16)
assert(vim.api.nvim_get_hl(0, { name = group, link = false }).fg == blue, "header-file icon must use the blue accent")
vim.cmd.colorscheme("onedark")
vim.wait(50)
assert(vim.api.nvim_get_hl(0, { name = group, link = false }).fg == blue, "theme reload must preserve the blue devicon")
print("Argv-file outline startup, immediate rail and persistent icon colors passed")
