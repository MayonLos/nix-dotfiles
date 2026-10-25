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
ws.attach()
vim.wait(80)
for _, r in pairs(ws.rails) do
	assert(vim.api.nvim_win_get_width(r.win) == 3, "tool rail width drift")
end
local doc = assert(ws.editor())
vim.wo[doc].winhighlight =
	"Normal:SnacksDashboardNormal,NormalNC:SnacksDashboardNormal,EndOfBuffer:SnacksDashboardEndOfBuffer"
vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = vim.api.nvim_win_get_buf(doc) })
assert(not vim.wo[doc].winhighlight:find("SnacksDashboard", 1, true), "dashboard colors leaked into editor")
vim.wo[doc].winhighlight = "Normal:NormalFloat,NormalNC:NormalFloat,WinBar:MayonPanelTitle,CursorLine:PmenuSel"
vim.api.nvim_exec_autocmds("BufWinEnter", { buffer = vim.api.nvim_win_get_buf(doc) })
assert(not vim.wo[doc].winhighlight:find("NormalFloat", 1, true), "auxiliary deep surface leaked into editor")
assert(ws.headers[doc] and vim.api.nvim_win_get_height(ws.headers[doc].win) == 1)
local tabs = table.concat(vim.api.nvim_buf_get_lines(ws.headers[doc].buf, 0, -1, false))
assert(tabs:find("example.lua", 1, true) and tabs:find("×", 1, true), "native document tabs missing")
local original_columns = vim.o.columns
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
vim.o.columns = 78
ws.refresh()
local header = ws.headers[doc]
local active = require("mayon.ui.tabline").active_buffer()
local seen = {}
local function assert_header_controls()
	local line = table.concat(vim.api.nvim_buf_get_lines(header.buf, 0, -1, false))
	local ellipsis = assert(line:find("⋯", 1, true), "overflow picker glyph is not visible")
	local ellipsis_column = vim.fn.strwidth(line:sub(1, ellipsis - 1)) + 1
	local picker_matches_glyph = false
	local arrow = line:find("›", 1, true)
	local next_matches_glyph = false
	for _, control in ipairs(header.controls) do
		if control.action == "picker" and control.left == ellipsis_column then
			picker_matches_glyph = true
		elseif control.action == "next" and arrow then
			local arrow_column = vim.fn.strwidth(line:sub(1, arrow - 1)) + 1
			next_matches_glyph = control.left == arrow_column and control.right == arrow_column
		end
	end
	assert(picker_matches_glyph, "picker click column does not match the visible ⋯")
	if arrow then
		assert(next_matches_glyph, "next-page click column does not match the visible ›")
	end
	assert(
		vim.fn.strwidth(line) == vim.api.nvim_win_get_width(header.win),
		"overflow header is not padded to its window width"
	)
end
for _ = 1, 12 do
	assert_header_controls()
	for _, range in ipairs(header.ranges) do
		seen[range.buf] = true
	end
	assert(seen[active], "active buffer disappeared from the paged header")
	local has_next = vim.tbl_contains(
		vim.tbl_map(function(control)
			return control.action
		end, header.controls or {}),
		"next"
	)
	if has_next then
		ws.page(doc, "next")
	else
		break
	end
end
for _, buf in ipairs(many) do
	assert(seen[buf], "buffer is unreachable through header pagination: " .. vim.api.nvim_buf_get_name(buf))
end
vim.o.columns = original_columns
ws.refresh()
vim.cmd.tabnew(file)
ws.attach()
vim.wait(80)
assert(ws.rails.left and ws.rails.right, "new tab has no tools")
for _, r in pairs(ws.rails) do
	assert(vim.api.nvim_win_get_tabpage(r.win) == vim.api.nvim_get_current_tabpage())
end
vim.cmd.tabclose()
vim.wait(80)
local editor = ws.editor()
vim.api.nvim_win_close(editor, true)
vim.wait(100)
for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
	assert(vim.bo[vim.api.nvim_win_get_buf(w)].filetype ~= "mayon_tabs", "orphan editor tabs")
end
ws.enabled = false
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
local getcmdwintype = vim.fn.getcmdwintype
vim.fn.getcmdwintype = function()
	return ":"
end
assert(ws.in_cmdwin(), "command window guard did not recognize an active command window")
assert(pcall(ws.attach), "workspace attach should safely skip command window")
vim.fn.getcmdwintype = getcmdwintype
print("Parser visibility, native workspace lifecycle, tabs and bigfile guards passed")

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
