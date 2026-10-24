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
for _, width in ipairs({ 40, 60, 80, 100, 120, 180 }) do
	vim.o.columns = width
	local status = vim.api.nvim_eval_statusline(vim.o.statusline, { maxwidth = width })
	local tabs = vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true, maxwidth = width })
	assert(status.str ~= "" and status.width <= width, "status line overflow")
	assert(tabs.width <= width, "tab line overflow")
end
-- Busy tool state must not displace unsaved/readonly information on a narrow
-- screen. Checking only final width would miss whole components folding away.
local attention = vim.api.nvim_create_namespace("workflow-attention")
local diagnostics = {}
for index = 1, 99 do
	diagnostics[#diagnostics + 1] = {
		lnum = 0,
		col = 0,
		message = "workflow fixture",
		severity = index <= 49 and vim.diagnostic.severity.ERROR or vim.diagnostic.severity.WARN,
	}
end
vim.diagnostic.set(attention, doc, diagnostics)
vim.bo[doc].modified, vim.bo[doc].readonly = true, true
vim.api.nvim_exec_autocmds("User", {
	pattern = "CodeCompanionRequestStarted",
	data = { id = "workflow-attention", adapter = { name = "DeepSeek" } },
})
for _, width in ipairs({ 40, 60, 80, 100, 160 }) do
	vim.o.columns = width
	vim.cmd.redrawstatus()
	local rail = vim.api.nvim_eval_statusline(vim.o.statusline, { maxwidth = width })
	assert(rail.str:find("●", 1, true), "unsaved marker disappeared at " .. width .. " columns")
	assert(rail.str:find("󰌾", 1, true), "readonly marker disappeared at " .. width .. " columns")
	assert(rail.str:find("49", 1, true) and rail.str:find("50", 1, true), "diagnostic counts disappeared")
end
vim.api.nvim_exec_autocmds("User", {
	pattern = "CodeCompanionRequestFinished",
	data = { id = "workflow-attention" },
})
vim.diagnostic.reset(attention, doc)
vim.bo[doc].modified, vim.bo[doc].readonly = false, false
vim.cmd.vnew()
local toolwin, toolbuf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
vim.bo.buftype = "nofile"
vim.bo.filetype = "snacks_picker_list"
tab.select(doc)
assert(vim.api.nvim_get_current_win() == docwin, "tab click chose the sidebar")
assert(vim.api.nvim_win_get_buf(toolwin) == toolbuf, "tab click replaced the sidebar")
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
vim.cmd.colorscheme("onedark-darker")
assert(vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg == 0x1f2329)
-- Surface colours must survive a theme reload after plugins have registered
-- their highlight groups. Text overlays must not punch holes in selected rows.
local function hl(name)
	return vim.api.nvim_get_hl(0, { name = name, link = false })
end
for _, name in ipairs({
	"NormalFloat",
	"FloatBorder",
	"FloatTitle",
	"Pmenu",
	"PmenuBorder",
	"SnacksPickerList",
}) do
	assert(hl(name).bg == hl("Normal").bg, name .. " has a disconnected background")
end
assert(hl("PmenuSel").bg == tonumber(require("mayon.generated").palette.selection:sub(2), 16))
for _, name in ipairs({ "RenderMarkdownH5", "RenderMarkdownH6" }) do
	assert(hl(name).fg == hl("Normal").fg)
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
