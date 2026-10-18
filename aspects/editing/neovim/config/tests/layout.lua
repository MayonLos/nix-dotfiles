-- Run from the repository root via tests/run.lua with isolated XDG paths.
-- The fixture creates and removes a private temporary project tree.
local root = vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)))
vim.opt.rtp:prepend(root)

local api = vim.api
local base = vim.fn.tempname()

local function run()
	vim.fn.mkdir(base, "p")
	vim.o.hidden = true
	vim.o.columns = 140

	local long_name = "这是一个很长的中文文件名保留百分号%与完整路径.md"
	local long_path = base .. "/" .. long_name
	local document_path = base .. "/另一个文档.md"
	vim.fn.writefile({ "project document" }, long_path)
	vim.fn.writefile({ "other document" }, document_path)
	vim.cmd.edit(vim.fn.fnameescape(long_path))
	local editor_win = api.nvim_get_current_win()
	local editor_buf = api.nvim_get_current_buf()

	vim.wo[editor_win].number = true
	vim.wo[editor_win].relativenumber = true
	vim.wo[editor_win].wrap = true
	vim.wo[editor_win].list = true
	vim.wo[editor_win].statuscolumn = "%l BODY"
	vim.wo[editor_win].signcolumn = "yes:1"

	local tabline = require("mayon.tabline")
	tabline.setup()
	local files = require("mayon.files")
	files.explorer({ cwd = base })
	local tree_win = api.nvim_get_current_win()
	local tree_buf = api.nvim_win_get_buf(tree_win)

	assert(vim.bo[tree_buf].filetype == "mayon-file-tree", "explorer must open the native file tree")
	assert(not vim.wo[tree_win].wrap, "tree labels must stay on one line")
	assert(not vim.wo[tree_win].list, "tree must not inherit list characters")
	assert(not vim.wo[tree_win].number and not vim.wo[tree_win].relativenumber, "tree must hide editor line numbers")
	assert(vim.wo[tree_win].statuscolumn == "", "tree must not inherit the editor status column")
	assert(vim.wo[tree_win].signcolumn == "no", "tree must not inherit editor signs")
	assert(vim.wo[editor_win].wrap, "opening the tree must preserve editor wrapping")
	assert(vim.wo[editor_win].list, "opening the tree must preserve editor list mode")
	assert(
		vim.wo[editor_win].number and vim.wo[editor_win].relativenumber,
		"opening the tree must preserve editor numbers"
	)
	assert(vim.wo[editor_win].statuscolumn == "%l BODY", "opening the tree must preserve the editor status column")
	assert(vim.wo[editor_win].signcolumn == "yes:1", "opening the tree must preserve editor signs")

	local tree_lines = table.concat(api.nvim_buf_get_lines(tree_buf, 0, -1, false), "\n")
	assert(tree_lines:find(long_name, 1, true), "tree must preserve long Chinese and percent-escaped names")

	local document_buf = api.nvim_create_buf(true, false)
	api.nvim_buf_set_name(document_buf, document_path)
	api.nvim_buf_set_lines(document_buf, 0, -1, false, { "other document" })
	api.nvim_set_current_win(tree_win)
	tabline.click(document_buf, 1, "l")
	assert(
		vim.wait(100, function()
			return api.nvim_get_current_buf() == document_buf
		end),
		"clicking a document tab from the tree must focus an editor window"
	)
	assert(api.nvim_win_is_valid(tree_win), "tab click must keep the tree window open")
	assert(api.nvim_win_get_buf(tree_win) == tree_buf, "tab click must never replace the tree with a document")
	assert(api.nvim_get_current_win() ~= tree_win, "document tab click must not leave focus in the tree")

	-- Supply the same generated preference that the real wrapper writes, without
	-- loading or editing a user's generated config.
	package.loaded["mayon.generated"] = { palette = { reducedMotion = true } }
	local editor = require("mayon.editor")
	editor.setup()
	local scroll_buf = api.nvim_create_buf(true, false)
	local lines = {}
	for index = 1, 240 do
		lines[index] = "line " .. index
	end
	api.nvim_buf_set_lines(scroll_buf, 0, -1, false, lines)
	api.nvim_win_set_buf(editor_win, scroll_buf)
	api.nvim_set_current_win(editor_win)
	vim.wo[editor_win].scrolloff = 0
	api.nvim_win_set_cursor(editor_win, { 80, 0 })

	local before = api.nvim_win_call(editor_win, vim.fn.winsaveview)
	api.nvim_win_call(editor_win, function()
		vim.cmd.normal({ args = { "3\004" }, bang = true })
	end)
	local native_view = api.nvim_win_call(editor_win, vim.fn.winsaveview)
	local native_cursor = api.nvim_win_get_cursor(editor_win)
	api.nvim_win_call(editor_win, function()
		vim.fn.winrestview(before)
	end)

	local timer_count = 0
	local new_timer = vim.uv.new_timer
	vim.uv.new_timer = function(...)
		timer_count = timer_count + 1
		return new_timer(...)
	end
	local scroll_ok, scroll_err = pcall(editor.scroll, "\004", 3)
	vim.uv.new_timer = new_timer
	assert(scroll_ok, "reduced-motion scroll must complete: " .. tostring(scroll_err))
	assert(timer_count == 0, "reduced-motion editor scroll must not create an animation timer")
	assert(
		vim.deep_equal(api.nvim_win_call(editor_win, vim.fn.winsaveview), native_view),
		"counted half-page scroll must reach the exact native target immediately"
	)
	assert(
		api.nvim_win_get_cursor(editor_win)[1] == native_cursor[1],
		"counted scroll must preserve native cursor semantics"
	)
end

local ok, err = xpcall(run, debug.traceback)
vim.fn.delete(base, "rf")
if not ok then
	io.stderr:write(err .. "\n")
	vim.cmd("cquit 1")
end
io.stdout:write("file tree, tab target, and reduced-motion scrolling checks passed\n")
