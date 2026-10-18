local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fs.dirname(vim.fs.dirname(source))
vim.opt.rtp:prepend(root)
if vim.env.NVIM_SNACKS_PATH and vim.env.NVIM_SNACKS_PATH ~= "" then
	vim.opt.rtp:prepend(vim.env.NVIM_SNACKS_PATH)
end

local fileops = require("mayon.features.fileops")
local original_notify = vim.notify
vim.notify = function() end

local function tempdir()
	local path = vim.fn.tempname()
	assert(vim.fn.mkdir(path, "p") == 1, "could not create isolated test directory")
	return path
end

local function read(path)
	return table.concat(vim.fn.readfile(path), "\n")
end

local function close_buffer(buf)
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end

-- Rename keeps unsaved buffer text and the next ordinary :write persists it.
do
	local dir = tempdir()
	local old, new = dir .. "/before.txt", dir .. "/after.txt"
	vim.fn.writefile({ "disk version" }, old)
	vim.cmd.edit(vim.fn.fnameescape(old))
	local buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "unsaved editor version" })
	local callback
	assert(fileops.rename_file({
		from = old,
		to = new,
		on_rename = function(to, from, ok)
			callback = { to, from, ok }
		end,
	}))
	assert(
		callback[1] == new and callback[2] == old and callback[3],
		"Snacks callback should receive the successful rename"
	)
	assert(vim.api.nvim_buf_get_name(buf) == new, "renamed buffer path should follow the file")
	assert(vim.bo[buf].modified, "unsaved buffer text should remain modified after rename")
	assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "unsaved editor version" }))
	local write_ok = pcall(vim.api.nvim_buf_call, buf, function()
		vim.cmd.write()
	end)
	assert(write_ok, "ordinary write should persist after a safe rename")
	assert(read(new) == "unsaved editor version", "ordinary write should safely save the renamed buffer")
	assert(
		not vim.bo[buf].modified and vim.bo[buf].buftype == "",
		"successful save should restore ordinary buffer state"
	)
	close_buffer(buf)
	vim.fn.delete(dir, "rf")
end

-- Existing targets and target buffers are never overwritten or adopted.
do
	local dir = tempdir()
	local old, target = dir .. "/source.txt", dir .. "/target.txt"
	vim.fn.writefile({ "source" }, old)
	vim.fn.writefile({ "keep target" }, target)
	local ok = fileops.rename_file({ from = old, to = target })
	assert(not ok and read(old) == "source" and read(target) == "keep target", "existing target must be preserved")
	local virtual = dir .. "/open-target.txt"
	vim.cmd.edit(vim.fn.fnameescape(old))
	local buf = vim.api.nvim_get_current_buf()
	local other = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_buf_set_name(other, virtual)
	assert(not fileops.rename_file({ from = old, to = virtual }), "open target buffer must block rename")
	assert(vim.api.nvim_buf_get_name(buf) == old and vim.fn.filereadable(old) == 1)
	close_buffer(other)
	close_buffer(buf)
	vim.fn.delete(dir, "rf")
end

-- An external write after rename blocks the editor buffer's normal save.
do
	local dir = tempdir()
	local old, new = dir .. "/before.txt", dir .. "/after.txt"
	vim.fn.writefile({ "original" }, old)
	vim.cmd.edit(vim.fn.fnameescape(old))
	local buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "unsaved editor version" })
	assert(fileops.rename_file({ from = old, to = new }))
	vim.fn.writefile({ "external version" }, new)
	local write_ok = pcall(vim.api.nvim_buf_call, buf, function()
		vim.cmd.write()
	end)
	assert(not write_ok, "normal write must report an external modification")
	vim.wait(1000, function()
		return vim.bo[buf].modified
	end, 10)
	assert(read(new) == "external version", "external file contents must not be overwritten")
	assert(vim.bo[buf].modified, "rejected save must leave the buffer modified")
	close_buffer(buf)
	vim.fn.delete(dir, "rf")
end

-- A rejected write makes :wq fail in a disposable child Neovim process.
do
	local dir = tempdir()
	local old, new = dir .. "/before.txt", dir .. "/after.txt"
	local child_script = dir .. "/write-quit.lua"
	local script = ([=[
vim.opt.rtp:prepend(%q)
local fileops = require("mayon.features.fileops")
vim.notify = function() end
vim.fn.writefile({ "original" }, %q)
vim.cmd.edit(vim.fn.fnameescape(%q))
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "unsaved editor version" })
assert(fileops.rename_file({ from = %q, to = %q }))
vim.fn.writefile({ "external version" }, %q)
local ok = pcall(vim.cmd, "wq")
assert(not ok, ":wq must fail when an external change invalidates the write guard")
assert(vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modified, "failed :wq must keep the modified buffer open")
assert(table.concat(vim.fn.readfile(%q), "\n") == "external version", "failed :wq must preserve external data")
print("guarded :wq aborted and retained the buffer")
vim.cmd("qa!")
]=]):format(root, old, old, old, new, new, new)
	vim.fn.writefile(vim.split(script, "\n", { plain = true }), child_script)
	local result = vim.system({ vim.v.progpath, "--clean", "--headless", "-l", child_script }, { text = true }):wait()
	assert(result.code == 0, "isolated :wq guard test failed: " .. (result.stderr or result.stdout or "unknown error"))
	assert(
		((result.stdout or "") .. (result.stderr or "")):find("guarded :wq aborted and retained the buffer", 1, true),
		"isolated child did not report the expected :wq guard: " .. (result.stderr or result.stdout or "no output")
	)
	assert(read(new) == "external version", "child process must preserve the externally modified file")
	vim.fn.delete(dir, "rf")
end

-- A BufWritePre failure must also abort :wq instead of being swallowed.
do
	local dir = tempdir()
	local old, new = dir .. "/before.txt", dir .. "/after.txt"
	local child_script = dir .. "/write-quit.lua"
	local script = ([=[
vim.opt.rtp:prepend(%q)
local fileops = require("mayon.features.fileops")
vim.notify = function() end
vim.fn.writefile({ "original" }, %q)
vim.cmd.edit(vim.fn.fnameescape(%q))
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "unsaved editor version" })
assert(fileops.rename_file({ from = %q, to = %q }))
vim.api.nvim_create_autocmd("BufWritePre", { buffer = buf, callback = function() error("injected pre-write failure") end })
local ok = pcall(vim.cmd, "wq")
assert(not ok, ":wq must fail when BufWritePre fails")
assert(vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modified, "failed :wq must keep the modified buffer open")
assert(table.concat(vim.fn.readfile(%q), "\n") == "original", "failed :wq must preserve external data")
print("guarded :wq aborted and retained the buffer")
vim.cmd("qa!")
]=]):format(root, old, old, old, new, new)
	vim.fn.writefile(vim.split(script, "\n", { plain = true }), child_script)
	local result = vim.system({ vim.v.progpath, "--clean", "--headless", "-l", child_script }, { text = true }):wait()
	assert(result.code == 0, "isolated :wq guard test failed: " .. (result.stderr or result.stdout or "unknown error"))
	assert(
		((result.stdout or "") .. (result.stderr or "")):find("guarded :wq aborted and retained the buffer", 1, true),
		"isolated child did not report the expected :wq guard: " .. (result.stderr or result.stdout or "no output")
	)
	assert(read(new) == "original", "child process must preserve the externally modified file")
	vim.fn.delete(dir, "rf")
end

-- Directory moves update nested buffer paths without dropping unsaved text.
do
	local dir = tempdir()
	local old, new = dir .. "/old", dir .. "/new"
	vim.fn.mkdir(old .. "/nested", "p")
	local child_old, child_new = old .. "/nested/file.txt", new .. "/nested/file.txt"
	vim.fn.writefile({ "disk" }, child_old)
	vim.cmd.edit(vim.fn.fnameescape(child_old))
	local buf = vim.api.nvim_get_current_buf()
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "unsaved child" })
	assert(fileops.rename_file({ from = old, to = new }))
	assert(vim.api.nvim_buf_get_name(buf) == child_new, "nested buffer path should follow directory rename")
	assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), { "unsaved child" }))
	vim.api.nvim_buf_call(buf, function()
		vim.cmd.write()
	end)
	assert(read(child_new) == "unsaved child", "nested buffer should retain a safe normal write")
	close_buffer(buf)
	vim.fn.delete(dir, "rf")
end

-- Missing trash tools refuse the operation without touching the path.
do
	local dir = tempdir()
	local path = dir .. "/keep.txt"
	vim.fn.writefile({ "keep me" }, path)
	local ok, err = fileops.trash(path, function()
		return ""
	end)
	assert(not ok and err:find("not deleted", 1, true), "missing trash command should reject the operation")
	assert(read(path) == "keep me", "missing trash command must leave the item untouched")
	vim.fn.delete(dir, "rf")
end

-- Exercise the real Snacks explorer delete chain. Its trash hook must reject
-- a directory containing a modified child buffer before resolving or running a
-- trash command; a successful hook would make explorer_del force-delete it.
do
	local snacks_ok, Snacks = pcall(require, "snacks")
	if not snacks_ok then
		assert(vim.env.NVIM_SNACKS_REQUIRED ~= "1", "Snacks integration test requires NVIM_SNACKS_PATH")
		print("Snacks explorer integration test skipped (NVIM_SNACKS_PATH is unset)")
	else
		local actions = require("snacks.explorer.actions")
		local tree = require("snacks.explorer.tree")
		fileops.setup()
		local util = Snacks.picker.util
		local old_confirm, old_path = util.confirm, util.path
		local old_update = actions.update
		local old_refresh = tree.refresh
		local old_error = Snacks.notify.error
		local old_system, old_exepath = vim.system, vim.fn.exepath
		local system_calls, resolve_calls = 0, 0
		local dir = tempdir()
		local child = dir .. "/nested/modified.txt"
		vim.fn.mkdir(vim.fs.dirname(child), "p")
		vim.fn.writefile({ "disk version" }, child)
		vim.cmd.edit(vim.fn.fnameescape(child))
		local buf = vim.api.nvim_get_current_buf()
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "unsaved version" })
		util.path = function(item)
			return item.file
		end
		util.confirm = function(_, callback)
			callback()
		end
		actions.update = function() end
		tree.refresh = function() end
		Snacks.notify.error = function() end
		vim.fn.exepath = function()
			resolve_calls = resolve_calls + 1
			return "/must-not-be-called/trash"
		end
		vim.system = function()
			system_calls = system_calls + 1
			return {
				wait = function()
					return { code = 0, stdout = "", stderr = "" }
				end,
			}
		end
		local picker = {
			selected = function()
				return { { file = dir } }
			end,
			list = { set_selected = function() end },
		}
		actions.actions.explorer_del(picker)
		assert(
			system_calls == 0 and resolve_calls == 0,
			"modified directory must be rejected before invoking a trash tool"
		)
		assert(
			vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].modified,
			"explorer delete must preserve the modified child buffer"
		)
		assert(read(child) == "disk version", "explorer delete must not move the disk version to trash")
		vim.system, vim.fn.exepath = old_system, old_exepath
		tree.refresh, actions.update = old_refresh, old_update
		util.confirm, util.path = old_confirm, old_path
		Snacks.notify.error = old_error
		close_buffer(buf)
		vim.fn.delete(dir, "rf")
	end
end

vim.notify = original_notify
print("file operation safety checks passed")
