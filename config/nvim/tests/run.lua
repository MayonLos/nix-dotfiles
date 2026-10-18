-- :luafile does not split trailing | commands. Keep failure handling in Lua
-- so startup/test errors cannot be hidden by a later successful :qa!.
local ok, err = xpcall(function()
	assert(vim.v.errmsg == "", "startup error: " .. vim.v.errmsg)
	dofile(assert(vim.env.NVIM_TEST_FILE, "NVIM_TEST_FILE is required"))
end, debug.traceback)
if not ok then
	io.stderr:write(tostring(err) .. "\n")
	vim.cmd("cquit 1")
end
vim.cmd("qa!")
