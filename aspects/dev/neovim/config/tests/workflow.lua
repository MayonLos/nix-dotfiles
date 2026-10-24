-- UI contracts against real Heirline/Navic/Snacks, using only temporary files.
local tab = require("mayon.ui.tabline")
local initial = vim.api.nvim_get_current_buf()
assert(not vim.tbl_contains(tab.buffers(), initial), "empty placeholder occupies a tab")
vim.api.nvim_buf_set_lines(initial, 0, -1, false, { "unsaved note" })
assert(vim.tbl_contains(tab.buffers(), initial), "unsaved unnamed work was hidden")
vim.bo[initial].modified = false
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local path = root .. "/中文%说明.md"
vim.fn.writefile({
	"# 标题",
	"",
	string.rep("中文文档长段落与专业术语 ", 40),
	"",
	"| 列 | 值 |",
	"| --- | --- |",
	"| 词 | 字 |",
}, path)
vim.lsp.enable("marksman", false)
vim.cmd.edit(vim.fn.fnameescape(path))
assert(vim.bo.filetype == "markdown" and vim.wo.wrap, "long Markdown is clipped")
local doc, docwin = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
local function contains_private_use(text)
	for index = 0, vim.fn.strchars(text) - 1 do
		local codepoint = vim.fn.char2nr(vim.fn.strcharpart(text, index, 1))
		if
			(codepoint >= 0xE000 and codepoint <= 0xF8FF)
			or (codepoint >= 0xF0000 and codepoint <= 0xFFFFD)
			or (codepoint >= 0x100000 and codepoint <= 0x10FFFD)
		then
			return true
		end
	end
	return false
end
for _, width in ipairs({ 40, 60, 80, 100, 120, 180 }) do
	vim.o.columns = width
	local status = vim.api.nvim_eval_statusline(vim.o.statusline, { maxwidth = width })
	local tabs = vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true, maxwidth = width })
	assert(status.str ~= "" and status.width <= width, "status line overflow")
	assert(tabs.width <= width, "tab line overflow")
	for _, forbidden in ipairs({ "×", "‾", "▔", "2 files" }) do
		assert(not tabs.str:find(forbidden, 1, true), "tab line contains obsolete decoration: " .. forbidden)
	end
	assert(not contains_private_use(tabs.str), "tab line should not contain devicon glyphs")
end
-- A diagnostic remains visible without making the statusline overflow narrow
-- layouts; unsaved work and close cancellation are covered below.
local attention = vim.api.nvim_create_namespace("workflow-attention")
local diagnostics = {}
diagnostics[1] = { lnum = 0, col = 0, message = "workflow fixture", severity = vim.diagnostic.severity.ERROR }
vim.diagnostic.set(attention, doc, diagnostics)
vim.bo[doc].modified, vim.bo[doc].readonly = true, true
for _, width in ipairs({ 40, 60, 80, 100, 160 }) do
	vim.o.columns = width
	vim.cmd.redrawstatus()
	local rail = vim.api.nvim_eval_statusline(vim.o.statusline, { maxwidth = width })
	assert(rail.width <= width, "diagnostics overflow the status line at " .. width .. " columns")
	if width >= 100 then
		assert(rail.str:find("▲1", 1, true), "single error should have a compact diagnostic indicator")
		assert(rail.str:find("AI · Copilot", 1, true), "statusline should identify Copilot as the AI provider")
	end
end
vim.diagnostic.reset(attention, doc)
vim.bo[doc].modified, vim.bo[doc].readonly = false, false
vim.cmd.vnew()
local toolwin, toolbuf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
vim.bo.buftype = "nofile"
vim.bo.filetype = "snacks_picker_list"
tab.select(doc)
assert(vim.api.nvim_get_current_win() == docwin, "tab click chose the sidebar")
assert(vim.api.nvim_win_get_buf(toolwin) == toolbuf, "tab click replaced the sidebar")
vim.bo[toolbuf].filetype = "nofile"
local confirm = vim.fn.confirm
vim.api.nvim_buf_set_lines(doc, 0, -1, false, { "unsaved document" })
vim.fn.confirm = function()
	return 3
end
require("snacks").bufdelete({ buf = doc })
vim.fn.confirm = confirm
assert(vim.api.nvim_buf_is_valid(doc) and vim.bo[doc].modified, "cancel discarded unsaved work")
vim.bo[doc].modified = false
local count = #vim.api.nvim_list_wins()
require("snacks").bufdelete({ buf = doc })
assert(#vim.api.nvim_list_wins() == count, "closing a buffer destroyed the layout")
local scratch = require("mayon.features.scratch")
local note = scratch.scratch()
vim.api.nvim_buf_set_lines(note, 0, -1, false, { "temporary scratch note" })
vim.api.nvim_exec_autocmds("BufLeave", { buffer = note })
assert(
	vim.wait(1000, function()
		return not vim.bo[note].modified
	end),
	"scratch was not saved"
)
assert(vim.fn.readfile(vim.api.nvim_buf_get_name(note))[1] == "temporary scratch note")
-- Big-file classification must keep expensive syntax/completion/folds off.
local big = root .. "/large.lua"
vim.fn.writefile({ string.rep("x", 1024 * 1024 + 1) }, big)
vim.cmd.edit(vim.fn.fnameescape(big))
assert(vim.bo.filetype == "bigfile", "large-file handler did not claim the buffer")
assert(vim.b.completion == false, "completion remained enabled for a large file")
assert(vim.wo.foldmethod == "manual", "Tree-sitter overrode the large-file fold guard")
assert(not vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()], "large file started highlighting")
vim.cmd.colorscheme("onedark")
assert(
	vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg
		== tonumber(require("mayon.generated").palette.bg:sub(2), 16)
)
-- Surface colours must survive a theme reload after plugins have registered
-- their highlight groups. Text overlays must not punch holes in selected rows.
local function hl(name)
	return vim.api.nvim_get_hl(0, { name = name, link = false })
end
for _, name in ipairs({
	"NormalFloat",
	"FloatBorder",
	"FloatTitle",
}) do
	assert(
		hl(name).bg == tonumber(require("mayon.generated").palette.deep:sub(2), 16),
		name .. " has a disconnected background"
	)
end
local popup_bg = tonumber(require("mayon.generated").palette.deep:sub(2), 16)
for _, name in ipairs({ "Pmenu", "PmenuBorder", "SnacksPickerList", "SnacksPickerNormal", "WhichKeyNormal" }) do
	assert(hl(name).bg == popup_bg, name .. " should use the deep popup surface")
end
assert(hl("PmenuSel").bg == tonumber(require("mayon.generated").palette.selection:sub(2), 16))
assert(hl("TabLineSel").bg == tonumber(require("mayon.generated").palette.bg:sub(2), 16))
assert(hl("MayonTabAccent").fg == tonumber(require("mayon.generated").palette.blue:sub(2), 16))
for _, name in ipairs({ "RenderMarkdownH5", "RenderMarkdownH6" }) do
	assert(hl(name).fg == tonumber(require("mayon.generated").palette.fg:sub(2), 16))
end
-- A literal percent and multibyte names must render as text, never statusline
-- directives, at narrow widths as well as in the full workspace rail.
local display = require("mayon.ui.text")
for _, width in ipairs({ 1, 2, 5, 12, 24 }) do
	local fitted = display.fit("中文 50% notes", width)
	local rendered = vim.api.nvim_eval_statusline(fitted, { maxwidth = width })
	assert(rendered.width <= width, "display text exceeds its cell budget")
end
local literal = vim.api.nvim_eval_statusline(display.fit("中文 50% notes"), { maxwidth = 40 })
assert(literal.str == "中文 50% notes", "literal percent was interpreted as statusline syntax")
assert(vim.v.errmsg == "", vim.v.errmsg)
print("Long documents, Unicode tabs, sidebar preservation, close cancellation and scratch passed")

-- The workspace explorer must own exactly one left column and follow the
-- current file's project root rather than the process HOME or an unrelated cwd.
local project = root .. "/workspace"
vim.fn.mkdir(project .. "/.git", "p")
vim.fn.mkdir(project .. "/nested", "p")
local project_file = project .. "/nested/entry.lua"
vim.fn.writefile({ "return true" }, project_file)
vim.cmd.edit(vim.fn.fnameescape(project_file))
vim.o.columns = 120
local explorer_mapping = vim.fn.maparg("<leader>e", "n", false, true)
assert(type(explorer_mapping.callback) == "function", "workspace explorer mapping is missing")
explorer_mapping.callback()
local snacks = require("snacks")
assert(
	vim.wait(2000, function()
		return #snacks.picker.get({ source = "explorer" }) > 0
	end),
	"explorer picker did not open"
)
local picker = snacks.picker.get({ source = "explorer" })[1]
assert(
	vim.wait(2000, function()
		return picker and #picker:items() > 0
	end),
	"explorer finder did not populate its list"
)
assert(
	picker and picker:cwd() == project,
	"explorer root should be the current git project: " .. tostring(picker and picker:cwd()) .. " != " .. project
)
assert(picker.opts.title == vim.fn.fnamemodify(project, ":t"):upper(), "explorer title should identify the project")
assert(not picker.opts.icons.git.enabled, "explorer should show git letters rather than status icons")
assert(
	vim.api.nvim_get_hl(0, { name = "SnacksPickerGitStatusModified", link = false }).fg
		== tonumber(require("mayon.generated").palette.orange:sub(2), 16),
	"Explorer modified status should use orange"
)
assert(
	not picker.opts.diagnostics and not picker.opts.diagnostics_open,
	"Explorer diagnostics should not crowd filenames"
)
local list_win = picker.list.win.win
assert(vim.api.nvim_win_is_valid(list_win), "explorer list window is missing")
assert(vim.api.nvim_win_get_width(list_win) == 30, "explorer sidebar should be 30 columns")
assert(tab.sidebar_width() == 31, "project title zone should align with the 30-column explorer")
local visible_windows = {}
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
	visible_windows[win] = true
end
local picker_windows = {}
local visible_panes = {}
for _, name in ipairs({ "input", "list", "preview" }) do
	local pane = picker[name]
	local win = pane and pane.win and pane.win.win
	local visible = win and visible_windows[win] or false
	local where = "hidden"
	if win and vim.api.nvim_win_is_valid(win) then
		local position = vim.api.nvim_win_get_position(win)
		where = string.format(
			"row=%d col=%d width=%d relative=%s",
			position[1],
			position[2],
			vim.api.nvim_win_get_width(win),
			vim.api.nvim_win_get_config(win).relative
		)
	end
	picker_windows[#picker_windows + 1] =
		string.format("%s win=%s visible=%s %s", name, tostring(win), tostring(visible), where)
	if visible then
		visible_panes[#visible_panes + 1] = name
	end
end
local picker_report = table.concat(picker_windows, "; ")
print("Explorer picker panes: " .. picker_report)
assert(picker.layout:is_hidden("input"), "explorer input should be hidden by default: " .. picker_report)
assert(
	not visible_windows[picker.input.win.win],
	"explorer input window should not be displayed by default: " .. picker_report
)
assert(
	#visible_panes == 1 and visible_panes[1] == "list",
	"explorer should display only the list pane: " .. picker_report
)
assert(
	vim.wo[list_win].winbar:find(picker.opts.title, 1, true),
	"uppercase project title should be shown in list winbar: " .. vim.wo[list_win].winbar
)
assert(
	vim.wo[list_win].winbar:find("MayonExplorerTitle", 1, true),
	"Explorer root title should use the muted highlight"
)
local _, title_count = vim.wo[list_win].winbar:gsub(picker.opts.title, "")
assert(title_count == 1, "Explorer root title should appear once")
local listbuf = vim.api.nvim_win_get_buf(list_win)
local explorer_lines = vim.api.nvim_buf_get_lines(listbuf, 0, -1, false)
local explorer_text = table.concat(explorer_lines, "\n")
for _, glyph in ipairs({ "├", "└", "│" }) do
	assert(not explorer_text:find(glyph, 1, true), "Explorer contains tree connector " .. glyph)
end
assert(
	explorer_text:find("▾", 1, true) or explorer_text:find("▸", 1, true),
	"Explorer should show disclosure arrows"
)
assert(not explorer_text:find(vim.fn.fnamemodify(project, ":t"), 1, true), "Explorer root title was repeated in rows")
local long_name = "extension-preserving-" .. string.rep("long-name-", 5) .. ".lua"
local formatted_long_file = picker.opts.format({ file = project .. "/nested/" .. long_name, dir = false }, picker)
assert(formatted_long_file[3][1]:match("%.lua$"), "Explorer truncation should preserve the extension")
assert(formatted_long_file[3][1]:find("…", 1, true), "long Explorer filenames should use an ellipsis")
assert(formatted_long_file[3][2] == "MayonExplorerFile", "Explorer filenames should use the normal foreground")
local formatted_directory = picker.opts.format({
	file = project .. "/nested",
	dir = true,
	open = true,
	parent = { file = project },
}, picker)
assert(formatted_directory[2][1] == "▾ 󰉋 " and formatted_directory[2][2] == "Directory")
assert(formatted_directory[3][1] == "nested" and formatted_directory[3][2] == "MayonExplorerFile")
local git_status = require("snacks.picker.format").file_git_status({ status = " M" }, picker)
assert(git_status[1].virt_text_pos == "right_align", "Git status letters should align at the row's right edge")
for _, item in ipairs(picker:items()) do
	assert(item.file ~= project, "Explorer repeated its root as a list item")
end
assert(picker.opts.focus == "list", "explorer should open focused on the visible list")
local rendered_tabs = vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true, maxwidth = 120 }).str
assert(
	not rendered_tabs:find(vim.fn.fnamemodify(project, ":t"), 1, true),
	"Explorer root should not be repeated in the tabline"
)
for _, forbidden in ipairs({ "×", "‾", "▔", "2 files" }) do
	assert(not rendered_tabs:find(forbidden, 1, true), "tabline contains obsolete decoration: " .. forbidden)
end
assert(not contains_private_use(rendered_tabs), "tabline should not contain devicon glyphs")
local project_win
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
	if vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win)) == project_file then
		project_win = win
	end
end
assert(project_win, "project document window should remain visible beside the explorer")
local rendered_status = vim.api.nvim_eval_statusline(vim.o.statusline, { maxwidth = 120, winid = project_win }).str
assert(rendered_status:find("entry.lua", 1, true), "statusline should show the current filename: " .. rendered_status)
assert(not rendered_status:find(project, 1, true), "statusline should show only the basename, not its path")
assert(rendered_status:find("AI · Copilot", 1, true), "statusline should show the selected AI provider")
assert(
	vim.wo[list_win].statuscolumn:find("MayonExplorerStatusColumn", 1, true),
	"explorer should use its selection rail"
)
vim.bo[vim.api.nvim_win_get_buf(project_win)].modified = true
local modified_tabline = vim.api.nvim_eval_statusline(vim.o.tabline, {
	use_tabline = true,
	maxwidth = 120,
	highlights = true,
})
assert(modified_tabline.str:find("●", 1, true), "modified document tab should display its unsaved marker")
local orange = tonumber(require("mayon.generated").palette.orange:sub(2), 16)
local orange_marker = false
for _, highlight in ipairs(modified_tabline.highlights or {}) do
	local colors = vim.api.nvim_get_hl(0, { name = highlight.group, link = false })
	if colors.fg == orange then
		orange_marker = true
	end
end
assert(orange_marker, "unsaved tab marker should use the orange palette highlight")
local search = picker.opts.actions.focus_input(picker)
assert(
	vim.wait(1000, function()
		return search.input.win.win and vim.api.nvim_get_current_win() == search.input.win.win
	end),
	"Explorer search should focus the centered input"
)
assert(search:cwd() == picker:cwd(), "Explorer search changed its project scope")
assert(search.opts.mayon_label == "Explorer 搜索")
assert(search.layout.root.opts.position == "float", "Explorer search must use the shared floating layout")
search:close()
assert(vim.api.nvim_win_get_width(picker.list.win.win) == 30, "Explorer search changed the navigation sidebar width")
picker:set_cwd(project .. "/nested")
picker:find()
assert(
	vim.wait(2000, function()
		return picker.opts.title == "NESTED" and vim.wo[picker.list.win.win].winbar:find("NESTED", 1, true)
	end),
	"Explorer title should follow root changes"
)
picker:close()
print("Project-root explorer, 30-column list, centered scoped search and workspace labels passed")
