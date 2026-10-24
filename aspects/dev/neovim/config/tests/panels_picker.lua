-- Picker configuration is testable without opening a picker window.
local pickers = require("mayon.ui.pickers")

local files = pickers.configure({ source = "files" })
assert(files.prompt == "❯ ", "picker input should use the blue chevron prompt")
assert(type(files.layout) == "table" and files.layout.layout.width == 0.9)
assert(files.layout.layout.title == "{title}", "picker layout should keep a clean source title")
assert(files.win.list.wo.cursorline and files.win.preview.wo.cursorline)
assert(files.win.list.wo.winhighlight:find("SnacksPickerListCursorLine", 1, true))
assert(files.win.preview.wo.winhighlight:find("SnacksPickerPreviewCursorLine", 1, true))

local grep = pickers.configure({ source = "grep" })
assert(type(grep.sort) == "function", "grep results should be grouped by file and line")
assert(type(grep.format) == "function", "grep rows should render file group labels and counts")
local first = { file = "a.nix", pos = { 2 }, idx = 1 }
local next_line = { file = "a.nix", pos = { 8 }, idx = 2 }
local next_file = { file = "b.nix", pos = { 1 }, idx = 3 }
assert(grep.sort(first, next_line) and grep.sort(next_line, next_file))
assert(not grep.sort(next_file, first))
local old_snacks = _G.Snacks
_G.Snacks = {
	picker = {
		highlight = {
			matches = function() end,
			offset = function()
				return 6
			end,
			format = function(item, text, out)
				out[#out + 1] = { text, "TestText" }
			end,
		},
	},
}
local items = { first, next_line, next_file }
local picker_fixture = {
	finder = { items = items },
	list = {
		items = items,
		count = function()
			return #items
		end,
		get = function(_, i)
			return items[i]
		end,
		win = {
			dim = function()
				return { width = 60 }
			end,
		},
	},
}
first.line, first.pos, first.positions = "first match", { 2 }, { 1 }
local header = { file = "a.nix", mayon_header = true, mayon_count = 2 }
local first_group = grep.format(header, picker_fixture)
assert(first_group[1][1]:find("a.nix", 1, true))
assert(first_group[2].virt_text_pos == "right_align")
assert(first_group[2].virt_text[1][1] == "2")
local following_match = grep.format(next_line, picker_fixture)
assert(following_match[1][2] == "SnacksPickerRow")
assert(grep.sort(header, first), "real file header must sort before its matches")
_G.Snacks = old_snacks

for _, source in ipairs({
	"files",
	"grep",
	"lsp_symbols",
	"lsp_workspace_symbols",
	"buffers",
	"recent",
	"help",
	"keymaps",
	"diagnostics",
}) do
	assert(pickers.labels[source], "missing shared picker label for " .. source)
end

local explorer = { source = "explorer", prompt = "existing", layout = "sidebar" }
assert(pickers.configure(explorer) == explorer)
assert(
	explorer.prompt == "❯ " and explorer.layout == "sidebar",
	"Explorer search should share the prompt and keep its sidebar"
)

print("Snacks picker layouts, grouping and Explorer isolation passed")

-- Exercise real native rows and scrolling, including many file boundaries.
vim.api.nvim_exec_autocmds("User", { pattern = "MayonVeryLazy" })
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
for i = 1, 30 do
	vim.fn.writefile({ "match one", "match two" }, dir .. ("/file-%03d.txt"):format(i))
end
local picker = Snacks.picker.grep({ cwd = dir, search = "match" })
assert(
	vim.wait(2000, function()
		return #picker.finder.items == 90 and not picker:is_active()
	end),
	"grouped native grep did not finish"
)
picker.list:view(70, nil, true)
local selected = picker.list:current()
assert(selected and selected.file, "native grep selection lost the target file")
local marks = vim.api.nvim_buf_get_extmarks(picker.list.win.buf, -1, 0, -1, { details = true })
for _, mark in ipairs(marks) do
	assert(not mark[4].virt_lines, "grep headers must occupy real rows")
end
local view = vim.api.nvim_win_call(picker.list.win.win, vim.fn.winsaveview)
assert(view.topline == 1, "native result rows must not desynchronize scrolling")
picker:close()
vim.fn.delete(dir, "rf")
