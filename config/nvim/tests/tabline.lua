-- Run from the repository root: nvim --clean --headless -c 'luafile config/nvim/tests/tabline.lua'
local root = vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)))
vim.opt.rtp:prepend(root)
local api, base = vim.api, vim.fn.tempname()
local tabline = require("mayon.tabline")
vim.fn.mkdir(base, "p")
vim.o.hidden = true
vim.o.columns = 150
vim.o.showtabline = 2
local function named(path)
	local buf = api.nvim_create_buf(true, false)
	api.nvim_buf_set_name(buf, base .. "/" .. path)
	return buf
end
local one, two = named("甲/相同%文件.lua"), named("乙/相同%文件.lua")
api.nvim_win_set_buf(0, one)
tabline.setup()
local function render()
	return api.nvim_eval_statusline(
		tabline.render():gsub("%%=", ""),
		{ use_tabline = true, maxwidth = 10000, highlights = true }
	)
end
local ok, err = xpcall(function()
	local initial = render()
	assert(
		initial.str:find("甲/相同%文件.lua", 1, true) and initial.str:find("乙/相同%文件.lua", 1, true),
		"duplicate names require distinct parent paths: " .. initial.str
	)
	assert(not initial.str:find("%%", 1, true), "literal percent must not be doubled")
	api.nvim_buf_set_lines(one, 0, -1, false, { "pending" })
	vim.bo[one].readonly = true
	local modified = render()
	assert(modified.str:find("●", 1, true) and modified.str:find("󰌾", 1, true), "file flags must be visible")
	local windows = #api.nvim_list_wins()
	vim.ui.select = function(_, _, callback)
		callback("Cancel")
	end
	tabline.close(one)
	vim.wait(30)
	assert(api.nvim_buf_is_valid(one) and vim.bo[one].modified, "middle/close must protect unsaved changes")
	assert(#api.nvim_list_wins() == windows, "cancel must keep layout")
	tabline.click(two, 1, "l")
	assert(
		vim.wait(100, function()
			return api.nvim_get_current_buf() == two
		end),
		"left click must switch buffer"
	)
	for index = 1, 10 do
		named("长目录" .. index .. "/相同%文件.lua")
	end
	local last = named("最后/选中的%中文文件.lua")
	api.nvim_win_set_buf(0, last)
	for _, columns in ipairs({ 28, 40, 60, 80, 140 }) do
		vim.o.columns = columns
		local out = render()
		assert(
			out.width <= columns,
			"buffer list must fit width " .. columns .. ": " .. out.str .. " width=" .. out.width
		)
		assert(
			out.str:find("选中", 1, true) or out.str:find("最后", 1, true),
			"selected buffer must remain visible: " .. out.str
		)
	end
	vim.o.columns = 140
	local hidden = named("隐藏/不该出现.lua")
	vim.bo[hidden].buflisted = false
	assert(not render().str:find("不该出现", 1, true), "unlisted buffer must be excluded")
	vim.cmd("tabnew")
	assert(tabline.render():find("%%999X"), "native tab-page close target must be present")
	assert(tabline.render():find("%%1T") and tabline.render():find("%%2T"), "native tab page controls must be present")
	tabline.scroll(1, 1, "l")
	vim.cmd("colorscheme habamax")
	vim.wait(30)
	assert(
		api.nvim_get_hl(0, { name = "MayonTabVisible" }).bold,
		"visible buffer style must survive colorscheme change"
	)
end, debug.traceback)
vim.fn.delete(base, "rf")
if not ok then
	io.stderr:write(err .. "\n")
	vim.cmd("cquit 1")
end
io.stdout:write("native tabline tests passed\n")
vim.cmd("qa!")
