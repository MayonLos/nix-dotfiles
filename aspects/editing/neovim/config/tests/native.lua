-- Run from the repository root with isolated XDG directories:
-- nvim --clean --headless -l config/nvim/tests/native.lua
-- Uses only temporary files; never touches the repository's Git index.
local root = vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)))
vim.opt.rtp:prepend(root)
local api = vim.api
local base = vim.fn.tempname()
vim.fn.mkdir(base .. "/old folder", "p")
local original_select, original_input, original_notify = vim.ui.select, vim.ui.input, vim.notify
local function run()
	local notices = {}
	vim.notify = function(message)
		notices[#notices + 1] = message
	end
	local files = require("mayon.files")
	local old = base .. "/old folder/中文 file.txt"
	vim.fn.writefile({ "on disk" }, old)
	vim.cmd.edit(vim.fn.fnameescape(old))
	local buf = api.nvim_get_current_buf()
	api.nvim_buf_set_lines(buf, 0, -1, false, { "unsaved text" })
	vim.cmd.vsplit()
	local windows = #api.nvim_list_wins()
	vim.ui.select = function(_, _, callback)
		callback("Cancel")
	end
	files.bufdelete({ buf = buf })
	assert(api.nvim_buf_is_valid(buf) and vim.bo[buf].modified, "cancel must preserve unsaved buffer")
	assert(#api.nvim_list_wins() == windows, "cancel must preserve splits")

	local renamed = base .. "/renamed folder"
	vim.ui.input = function(_, callback)
		callback(renamed)
	end
	files.rename(base .. "/old folder")
	assert(vim.uv.fs_stat(renamed .. "/中文 file.txt"), "directory rename must move file")
	assert(api.nvim_buf_get_name(buf) == renamed .. "/中文 file.txt", "directory rename must update child buffer")
	assert(vim.bo[buf].modified, "rename must preserve pending edits")
	assert(vim.fn.readfile(renamed .. "/中文 file.txt")[1] == "on disk", "rename must not overwrite saved content")

	local collision = base .. "/existing.txt"
	vim.fn.writefile({ "keep" }, collision)
	vim.ui.input = function(_, callback)
		callback(collision)
	end
	files.rename()
	assert(vim.fn.readfile(collision)[1] == "keep", "rename must never overwrite an existing target")
	local dangling = base .. "/dangling.txt"
	assert(vim.uv.fs_symlink(base .. "/missing.txt", dangling))
	vim.ui.input = function(_, callback)
		callback(dangling)
	end
	files.rename()
	assert(vim.uv.fs_lstat(dangling).type == "link", "rename must preserve dangling destination symlinks")
	assert(api.nvim_buf_get_name(buf) == renamed .. "/中文 file.txt", "rejected rename must preserve buffer name")
	vim.ui.select = function(_, _, callback)
		callback("Save and close")
	end
	files.bufdelete({ buf = buf })
	assert(not api.nvim_buf_is_valid(buf), "save and close must delete original buffer")
	assert(#api.nvim_list_wins() == windows, "buffer deletion must preserve splits")
	assert(vim.fn.readfile(renamed .. "/中文 file.txt")[1] == "unsaved text", "save choice must write pending edits")

	vim.cmd.edit(vim.fn.fnameescape(renamed .. "/中文 file.txt"))
	local guarded = api.nvim_get_current_buf()
	api.nvim_buf_set_lines(guarded, 0, -1, false, { "pending after rename" })
	local guarded_path = base .. "/guarded.txt"
	vim.ui.input = function(_, callback)
		callback(guarded_path)
	end
	files.rename()
	vim.fn.writefile({ "external changes must survive" }, guarded_path)
	pcall(api.nvim_buf_call, guarded, function()
		vim.cmd("write")
	end)
	assert(
		vim.fn.readfile(guarded_path)[1] == "external changes must survive",
		"first save after rename must protect external changes"
	)
	assert(vim.bo[guarded].modified, "refused save must preserve pending edits")
	vim.bo[guarded].modified = false
	vim.cmd.enew()

	local editor = require("mayon.editor")
	editor.setup()
	local value = vim.wo.wrap
	editor.toggle("wrap")
	assert(vim.wo.wrap ~= value, "wrap toggle must change the current window")
	editor.toggle("wrap")
	assert(vim.wo.wrap == value, "second toggle must restore wrap")
	local statuscolumn, laststatus = vim.wo.statuscolumn, vim.o.laststatus
	editor.zen()
	assert(vim.o.laststatus == 0 and vim.wo.statuscolumn == "", "Zen must hide chrome")
	editor.zen()
	assert(vim.o.laststatus == laststatus and vim.wo.statuscolumn == statuscolumn, "Zen must restore chrome")
	local large = base .. "/large.txt"
	local file = assert(io.open(large, "wb"))
	file:write(string.rep("x", 1024 * 1024 + 1))
	file:close()
	vim.cmd.edit(vim.fn.fnameescape(large))
	assert(vim.b.mayon_bigfile, "opening a large file must activate protection")
	assert(not vim.diagnostic.is_enabled({ bufnr = 0 }), "large file diagnostics must stay disabled")

	local ui = require("mayon.ui")
	ui.setup()
	local calls = 0
	ui.input({ prompt = "headless" }, function(value)
		calls = calls + 1
		assert(value == nil)
	end)
	assert(calls == 1, "headless input must cancel once")
	local first = ui.notify("first", vim.log.levels.INFO, { timeout = false })
	ui.notify("replacement", vim.log.levels.WARN, { replace = first, timeout = false })
	local history = ui.history()
	assert(#history == 1 and history[1].message == "replacement", "replacement must update its history entry")
end
local ok, err = xpcall(run, debug.traceback)
vim.ui.select, vim.ui.input, vim.notify = original_select, original_input, original_notify
vim.fn.delete(base, "rf")
if not ok then
	io.stderr:write(err .. "\n")
	vim.cmd("cquit 1")
end
io.stdout:write("native file protection, editor state, and headless UI checks passed\n")
vim.cmd("qa!")
