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
assert(ws.attach == nil and ws.page == nil and ws.rails == nil and ws.headers == nil)
local doc = assert(ws.editor(), "workspace did not locate the document window")
vim.wo[doc].winhighlight =
	"Normal:SnacksDashboardNormal,NormalNC:SnacksDashboardNormal,EndOfBuffer:SnacksDashboardEndOfBuffer"
vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = vim.api.nvim_win_get_buf(doc) })
assert(not vim.wo[doc].winhighlight:find("SnacksDashboard", 1, true), "dashboard colors leaked into editor")
vim.wo[doc].winhighlight = "Normal:NormalFloat,NormalNC:NormalFloat,WinBar:MayonPanelTitle,CursorLine:PmenuSel"
vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = vim.api.nvim_win_get_buf(doc) })
assert(not vim.wo[doc].winhighlight:find("NormalFloat", 1, true), "auxiliary float surface leaked into editor")
local tabs = require("mayon.ui.tabline")
local active = tabs.active_buffer()
assert(vim.tbl_contains(tabs.buffers(), active), "active document is missing from buffer navigation")
assert(
	vim.wait(500, function()
		return vim.o.showtabline == 2 and vim.o.tabline ~= ""
	end),
	"document header should occupy the top row"
)
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
vim.api.nvim_set_current_buf(many[12])
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
assert(not vim.tbl_contains(tabs.buffers(), health), "health buffer appeared in document navigation")
tabs.select(many[1])
assert(vim.api.nvim_get_current_win() == doc, "file selection did not return to the document window")
assert(vim.api.nvim_win_get_buf(tool_window) == health, "file selection replaced the health tool window")
vim.api.nvim_win_close(tool_window, true)
vim.api.nvim_set_current_buf(many[12])
assert(tabs.active_buffer() == many[12], "active document identity was lost")
assert(vim.api.nvim_get_current_buf() == many[12], "document selection should update the editing buffer")
local snacks = require("snacks")
local pick_buffers, buffers_picked = snacks.picker.buffers, false
snacks.picker.buffers = function()
	buffers_picked = true
end
local buffer_picker = vim.fn.maparg("<leader>,", "n", false, true)
assert(type(buffer_picker.callback) == "function", "buffer picker key should remain available")
buffer_picker.callback()
assert(buffers_picked, "buffer picker key did not open the picker")
snacks.picker.buffers = pick_buffers
local diagnostic_ns = vim.api.nvim_create_namespace("buffer-navigation-status-test")
vim.diagnostic.set(diagnostic_ns, many[12], {
	{ lnum = 0, col = 0, message = "toolbar error", severity = vim.diagnostic.severity.ERROR },
})
vim.bo[many[12]].modified = true
vim.cmd.redrawstatus()
local error_status = vim.api.nvim_eval_statusline(vim.o.statusline, { maxwidth = vim.o.columns })
assert(error_status.str:find("●1", 1, true), "diagnostic count should appear in the minimal statusline")
vim.diagnostic.reset(diagnostic_ns, many[12])
vim.bo[many[12]].modified = false
vim.bo[many[12]].readonly = false
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
print("Parser visibility, buffer navigation and bigfile guards passed")

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
