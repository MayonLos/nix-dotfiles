-- Snacks pickers use a full-width top shelf; previews are opt-in and the
-- Project tool keeps an on-demand file navigation entry.
local pickers = require("mayon.ui.pickers")
local files = pickers.configure({ source = "files" })
assert(files.prompt == "❯ ", "general picker input should retain its prompt")
assert(files.layout().preview == false, "general picker should not open a default preview")
assert(
	files.layout().layout.width == 0 and files.layout().layout.col == 0 and files.layout().layout.row == 0,
	"picker should occupy the top width"
)
assert(files.layout().layout.height == math.floor(vim.o.lines * 0.28), "picker height should use 28% of the editor")
assert(files.layout().layout.border == "none", "picker should not add an outer frame")
assert(files.layout().layout[1][1].border == "bottom", "picker input should use a fine lower rule")
assert(files.win.list.wo.cursorline and files.win.list.wo.cursorlineopt == "line")
assert(files.win.list.wo.winhighlight:find("SnacksPickerListCursorLine", 1, true))
local file_layout = vim.inspect(files.layout().layout)
assert(file_layout:find('win = "preview"', 1, true), "hidden preview must remain available to Alt-p")
local long_path = "/tmp/workspace/" .. string.rep("long-parent-name/", 5) .. "math_preview.lua"
local file_picker = {
	list = { win = {
		dim = function()
			return { width = 60 }
		end,
	} },
	cwd = function()
		return "/tmp/workspace"
	end,
}
local file_row = files.format({ file = long_path }, file_picker)
local expected_file_icon = require("mayon.ui.icons").get(long_path)
assert(file_row[1][1] == expected_file_icon and file_row[1][2]:match("^DevIcon"), "file rows need colored devicons")
assert(file_row[2][1] == "math_preview.lua", "long parent paths must preserve the filename budget")
assert(file_row[3].virt_text_pos == "right_align", "file parent path should stay aligned at the right edge")
assert(
	vim.fn.strdisplaywidth(file_row[3].virt_text[1][1]) <= 36,
	"long parent paths should truncate within their reserved width"
)

local grep = pickers.configure({ source = "grep" })
assert(grep.finder == nil and grep.sort == nil, "grep should use native Snacks results without regrouping")
assert(type(grep.format) == "function", "grep rows should place the path at the right edge")
local old_snacks = _G.Snacks
_G.Snacks = {
	picker = {
		highlight = {
			matches = function() end,
			offset = function()
				return 4
			end,
			format = function(item, _, out)
				out[#out + 1] = { item.text, "TestText" }
			end,
		},
	},
}
local match = { file = "/tmp/a.nix", pos = { 8 }, line = 'name = "fixture"', positions = { 9 }, text = "fixture" }
local row = grep.format(match, {})
assert(
	not match.mayon_header and row[1][1]:find("8", 1, true),
	"grep row should represent one match and its line number"
)
assert(row[#row].virt_text_pos == "right_align", "grep result path should be right aligned")
assert(row[#row].virt_text[#row[#row].virt_text][1] == "a.nix", "grep result should show the matching file at right")
_G.Snacks = old_snacks
for _, source in ipairs({
	"files",
	"grep",
	"grep_word",
	"grep_buffers",
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
local explorer_opts = pickers.configure({ source = "explorer" })
assert(explorer_opts.prompt == "⌕ ", "Project should expose the native filter input")

-- Open a real Project tool and verify its fixed-width input/list surface.
vim.api.nvim_exec_autocmds("User", { pattern = "MayonVeryLazy" })
local project = vim.fn.tempname() .. "/workspace"
vim.fn.mkdir(project .. "/.git", "p")
vim.fn.mkdir(project .. "/nested", "p")
local project_file = project .. "/nested/entry.lua"
vim.fn.writefile({ "return true" }, project_file)
vim.cmd.edit(vim.fn.fnameescape(project_file))
vim.o.columns = 120
local explorer_mapping = vim.fn.maparg("<leader>e", "n", false, true)
assert(type(explorer_mapping.callback) == "function", "workspace Project mapping is missing")
explorer_mapping.callback()
local snacks = require("snacks")
assert(
	vim.wait(2000, function()
		return #snacks.picker.get({ source = "explorer" }) > 0
	end),
	"Project picker did not open"
)
local picker = snacks.picker.get({ source = "explorer" })[1]
assert(
	vim.wait(2000, function()
		return picker and #picker:items() > 0
	end),
	"Project finder did not populate"
)
assert(picker:cwd() == project, "Project root should follow the current git repository")
local list_win = picker.list.win.win
assert(
	vim.api.nvim_win_is_valid(list_win) and vim.api.nvim_win_get_width(list_win) == 34,
	"Project rail should be 34 columns"
)
assert(picker.opts.prompt == "⌕ ", "Project filter prompt should be the native search input")
assert(not picker.layout:is_hidden("input"), "Project input should be visible by default")
assert(picker.layout:is_hidden("preview") or not picker.preview.win:valid(), "Project should not open a preview pane")
local visible = {}
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
	visible[win] = true
end
assert(visible[picker.input.win.win], "native Project input window is not visible")
assert(visible[list_win], "Project list window is not visible")
assert(not visible[picker.preview.win.win], "Project unexpectedly displayed a preview")
local item
for _, candidate in ipairs(picker:items()) do
	if candidate.file == project_file then
		item = candidate
		break
	end
end
assert(item, "Project list did not include the fixture file")
local formatted = picker.opts.format(item, picker)
local icon, icon_hl = require("mayon.ui.icons").get(project_file)
assert(formatted[2][1] == icon and icon_hl:match("^DevIcon"), "Project file should keep its colored type icon")
assert(formatted[1][1] == "  ", "Project indentation should use two-column increments")
local short_name = "math_preview.lua"
local short_item = {
	file = project .. "/nested/" .. short_name,
	dir = false,
	parent = { file = project .. "/nested", parent = { file = project } },
}
local short_row = picker.opts.format(short_item, picker)
assert(short_row[3][1] == short_name, "Project should keep filenames whole when they fit")
local long_name = "extension-preserving-" .. string.rep("long-name-", 5) .. ".lua"
local long_row = picker.opts.format({ file = project .. "/nested/" .. long_name, dir = false }, picker)
assert(long_row[3][1]:match("%.lua$"), "Project truncation should preserve extensions")
assert(long_row[3][1]:find("…", 1, true), "very long Project filenames should use a middle ellipsis")
picker:close()

-- A real grep result has one picker item per match and no synthetic group rows.
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
for i = 1, 5 do
	vim.fn.writefile({ "match-one", "match-two", "other" }, dir .. ("/file-%03d.txt"):format(i))
end
local grep_picker = Snacks.picker.grep({ cwd = dir, search = "match-" })
assert(
	vim.wait(2000, function()
		return #grep_picker.finder.items == 10 and not grep_picker:is_active()
	end),
	"native grep did not return one item per matching line"
)
for _, candidate in ipairs(grep_picker.finder.items) do
	assert(not candidate.mayon_header, "grep finder inserted a synthetic file header")
	assert(
		candidate.text and candidate.file and candidate.pos,
		"grep item should retain native line/file/position data"
	)
end
local live_row = grep_picker.opts.format(grep_picker.finder.items[1], grep_picker)
assert(live_row[#live_row].virt_text_pos == "right_align", "native grep path should remain right aligned")
grep_picker:update_titles()
local grep_footer = vim.api.nvim_win_get_config(grep_picker.input.win.win).footer
assert(
	grep_footer and vim.inspect(grep_footer):find("matches", 1, true),
	"live grep count should render in the right-side input footer"
)
grep_picker:close()
vim.fn.delete(dir, "rf")

-- A resize callback queued before close must not rebuild released picker panes.
local resizing = Snacks.picker.files({ cwd = project, show_delay = 0 })
assert(
	vim.wait(2000, function()
		return resizing.layout ~= nil
	end),
	"file picker layout did not initialize"
)
vim.v.errmsg = ""
vim.api.nvim_exec_autocmds("VimResized", {})
resizing:close()
vim.wait(100)
assert(vim.v.errmsg == "", "closed picker resize callback failed: " .. vim.v.errmsg)
print("Project input, compact pickers, native grep rows and resize-close passed")

-- Every picker starts without a preview; Alt-p adds context and survives resize.
vim.o.columns, vim.o.lines = 180, 50
for _, name in ipairs({ "grep", "lsp_references", "lsp_symbols", "git_log", "diagnostics" }) do
	assert(not pickers.configure({ source = name }).layout().preview, name .. " should stay compact")
end
local preview = Snacks.picker.files({ cwd = project, show_delay = 0 })
assert(vim.wait(1000, function()
	return preview.layout ~= nil
end))
preview:action("toggle_preview")
assert(preview.preview.win:valid() and not preview.layout:is_hidden("preview"), "Alt-p did not open files preview")
vim.o.columns = 90
preview:set_layout()
assert(not preview.layout:is_hidden("preview"), "narrow picker should keep an explicitly opened preview")
vim.o.columns = 180
preview:set_layout()
assert(not preview.layout:is_hidden("preview"), "resize lost the explicit preview preference")
preview:action("toggle_preview")
assert(preview.layout:is_hidden("preview"))
preview:close()
