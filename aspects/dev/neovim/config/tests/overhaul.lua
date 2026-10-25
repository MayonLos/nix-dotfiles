-- Exercise native workspace lifecycle and expensive-feature guards together.
for _, lang in ipairs({
	"lua",
	"nix",
	"rust",
	"go",
	"latex",
	"css",
	"html",
	"javascript",
	"tsx",
	"typst",
	"vue",
	"regex",
}) do
	assert(
		#vim.api.nvim_get_runtime_file("parser/" .. lang .. ".so", false) > 0,
		"parser absent before packadd: " .. lang
	)
end
assert(vim.opt.listchars:get().tab == "  ")
assert(require("snacks").config.image.mermaid.enabled == false)
assert(require("mayon.ui.extras").color_options().enable_named_colors == false)
vim.o.columns = 200
vim.o.lines = 60
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local file = root .. "/example.lua"
vim.fn.writefile({ "local answer = 42", "return answer" }, file)
vim.cmd.edit(file)
local dashboard_window = vim.api.nvim_get_current_win()
require("snacks").dashboard.open({ win = dashboard_window, buf = vim.api.nvim_create_buf(false, true) })
vim.cmd("edit! " .. vim.fn.fnameescape(file))
vim.api.nvim_exec_autocmds("User", { pattern = "SnacksDashboardUpdatePost" })
assert(
	not vim.wo[dashboard_window].winhighlight:find("SnacksDashboard", 1, true),
	"hidden dashboard reclaimed the editor window"
)
local ws = require("mayon.ui.workspace")
ws.setup()
assert(type(ws.action) == "function" and type(ws.editor) == "function")
assert(type(ws.buffer_labels) == "function")
assert(ws.attach == nil and ws.page == nil and ws.rails == nil and ws.headers == nil)
local doc = assert(ws.editor(), "workspace did not locate the document window")
vim.wo[doc].winhighlight =
	"Normal:SnacksDashboardNormal,NormalNC:SnacksDashboardNormal,EndOfBuffer:SnacksDashboardEndOfBuffer"
vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = vim.api.nvim_win_get_buf(doc) })
assert(not vim.wo[doc].winhighlight:find("SnacksDashboard", 1, true), "dashboard colors leaked into editor")
vim.wo[doc].winhighlight = "Normal:NormalFloat,NormalNC:NormalFloat,WinBar:MayonPanelTitle,CursorLine:PmenuSel"
vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = vim.api.nvim_win_get_buf(doc) })
assert(not vim.wo[doc].winhighlight:find("NormalFloat", 1, true), "auxiliary deep surface leaked into editor")
local toolbar = require("mayon.ui.toolbar")
local original_columns = vim.o.columns
vim.o.columns = 78
local active = require("mayon.ui.tabline").active_buffer()
local rendered_toolbar =
	vim.api.nvim_eval_statusline(toolbar.render(), { use_tabline = true, maxwidth = vim.o.columns })
assert(rendered_toolbar.width <= vim.o.columns, "toolbar overflowed the top row")
assert(rendered_toolbar.str:find("example.lua", 1, true), "active file is missing from the toolbar")
for _, obsolete in ipairs({ "×", "Run", "Search Everywhere" }) do
	assert(not rendered_toolbar.str:find(obsolete, 1, true), "toolbar contains removed control: " .. obsolete)
end
local palette = require("mayon.generated").palette
local pill = vim.api.nvim_get_hl(0, { name = "MayonTabPill", link = false })
assert(pill.bg == tonumber(palette.selection:sub(2), 16), "selected document pill should use selection background")
assert(pill.fg == tonumber(palette.brightFg:sub(2), 16), "selected document pill should use bright foreground")
local many = {}
for i = 1, 12 do
	local group = i == 1 and "alpha" or i == 2 and "beta" or ("group" .. i)
	local name = i <= 2 and "init.lua" or ("document-%02d.lua"):format(i)
	local path = root .. "/" .. group .. "/" .. name
	vim.fn.mkdir(vim.fs.dirname(path), "p")
	vim.fn.writefile({ "return " .. i }, path)
	local buf = vim.fn.bufadd(path)
	vim.fn.bufload(buf)
	vim.bo[buf].buflisted = true
	many[#many + 1] = buf
end
local labels = ws.buffer_labels(many)
assert(
	labels[many[1]] == "alpha/init.lua" and labels[many[2]] == "beta/init.lua",
	"duplicate basenames lack unique parent suffixes"
)
vim.api.nvim_set_current_buf(many[12])
vim.cmd.redrawtabline()
local tabs = require("mayon.ui.tabline")
local excluded_types = {
	"checkhealth",
	"grug-far",
	"grug_far",
	"oil",
	"aerial",
	"trouble",
	"neogitstatus",
	"neogitcommit",
	"snacks_picker_list",
	"snacks_dashboard",
	"codecompanion",
	"codecompanion_history",
	"claudecode",
	"claudecode_terminal",
	"help",
	"man",
	"qf",
}
local tool_buffers = {}
for index, filetype in ipairs(excluded_types) do
	local tool = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(tool, root .. "/tool-buffer-" .. index)
	vim.bo[tool].filetype = filetype
	tool_buffers[#tool_buffers + 1] = tool
end
local visible_documents = tabs.buffers()
for _, tool in ipairs(tool_buffers) do
	assert(
		not vim.tbl_contains(visible_documents, tool),
		"tool buffer entered document tabs: " .. vim.bo[tool].filetype
	)
end
vim.cmd.vnew()
local tool_window = vim.api.nvim_get_current_win()
local health = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_name(health, root .. "/health-report")
vim.bo[health].filetype = "checkhealth"
vim.api.nvim_set_current_win(doc)
assert(tabs.active_buffer() == many[12], "document was not active before opening health")
vim.api.nvim_win_set_buf(tool_window, health)
vim.api.nvim_set_current_win(tool_window)
assert(tabs.active_buffer() == many[12], "health buffer replaced the remembered active document")
local health_toolbar = vim.api.nvim_eval_statusline(toolbar.render(), { use_tabline = true, maxwidth = vim.o.columns })
assert(not health_toolbar.str:find("health-report", 1, true), "health buffer appeared in document tabs")
tabs.select(many[1])
assert(vim.api.nvim_get_current_win() == doc, "file selection did not return to the document window")
assert(vim.api.nvim_win_get_buf(tool_window) == health, "file selection replaced the health tool window")
vim.api.nvim_win_close(tool_window, true)
vim.api.nvim_set_current_buf(many[12])
vim.cmd.redrawtabline()
rendered_toolbar = vim.api.nvim_eval_statusline(toolbar.render(), { use_tabline = true, maxwidth = vim.o.columns })
assert(rendered_toolbar.str:find("document-12.lua", 1, true), "active file disappeared when the toolbar overflowed")
local active_icon = require("mayon.ui.icons").get(vim.api.nvim_buf_get_name(many[12]))
assert(rendered_toolbar.str:find(active_icon, 1, true), "active document lost its filetype icon")
assert(rendered_toolbar.width <= vim.o.columns, "overflow toolbar exceeded the available width")
local all_labels = ws.buffer_labels(require("mayon.ui.tabline").buffers())
local visible_tabs = 0
for _, label in pairs(all_labels) do
	if rendered_toolbar.str:find(label, 1, true) then
		visible_tabs = visible_tabs + 1
	end
end
local hidden_count = tonumber(rendered_toolbar.str:match("%+(%d+)"))
assert(hidden_count == #require("mayon.ui.tabline").buffers() - visible_tabs, "toolbar overflow count is not exact")
local snacks = require("snacks")
local pick_buffers, buffers_picked = snacks.picker.buffers, false
snacks.picker.buffers = function()
	buffers_picked = true
end
toolbar.click(4)
assert(
	vim.wait(500, function()
		return buffers_picked
	end),
	"+N overflow control did not open the buffer picker"
)
snacks.picker.buffers = pick_buffers
local diagnostic_ns = vim.api.nvim_create_namespace("toolbar-error-test")
vim.diagnostic.set(diagnostic_ns, many[12], {
	{ lnum = 0, col = 0, message = "toolbar error", severity = vim.diagnostic.severity.ERROR },
})
vim.bo[many[12]].modified = true
vim.cmd.redrawtabline()
local error_tabs = vim.api.nvim_eval_statusline(toolbar.render(), { use_tabline = true, maxwidth = vim.o.columns })
assert(error_tabs.str:find("●", 1, true), "tab status dot disappeared for a buffer with an error")
assert(
	vim.api.nvim_get_hl(0, { name = "MayonTabError", link = false }).fg == tonumber(palette.red:sub(2), 16),
	"tab error dot is not red"
)
vim.diagnostic.reset(diagnostic_ns, many[12])
vim.bo[many[12]].modified = false
vim.bo[many[12]].readonly = true
local readonly_tabs = vim.api.nvim_eval_statusline(toolbar.render(), { use_tabline = true, maxwidth = vim.o.columns })
assert(readonly_tabs.str:find("·", 1, true), "read-only buffer should use a quiet status dot")
assert(
	vim.api.nvim_get_hl(0, { name = "MayonTabReadonly", link = false }).fg == tonumber(palette.muted:sub(2), 16),
	"read-only status should remain muted"
)
vim.bo[many[12]].readonly = false
vim.o.columns = original_columns
vim.api.nvim_set_current_win(doc)
local big = root .. "/large.lua"
vim.fn.writefile({ string.rep("x", 1024 * 1024 + 10) }, big)
vim.cmd.edit(big)
assert(vim.bo.filetype == "bigfile")
assert(not require("snacks").config.scroll.filter(vim.api.nvim_get_current_buf()), "bigfile scroll still animated")
assert(not vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()])
for _, key in ipairs({ "<A-1>", "<A-2>", "<A-7>", "<A-F12>", "<leader>?", "<leader>;", "<leader>rr" }) do
	assert(vim.fn.maparg(key, "n") ~= "" or vim.fn.maparg(key, "n", false, true).callback, "missing tool key " .. key)
end
assert(not package.loaded["nvim-navic"] and not package.loaded.colorizer)
print("Parser visibility, toolbar lifecycle and bigfile guards passed")

-- A resize scheduled before a picker closes must not rebuild released windows.
vim.cmd.edit(file)
local resizing = require("snacks").picker.files({ cwd = root, show_delay = 0 })
vim.wait(100, function()
	return resizing.layout ~= nil
end)
assert(resizing.layout, "picker layout did not initialize")
vim.v.errmsg = ""
vim.api.nvim_exec_autocmds("VimResized", {})
resizing:close()
vim.wait(100)
assert(vim.v.errmsg == "", "closed picker resize callback failed: " .. vim.v.errmsg)
