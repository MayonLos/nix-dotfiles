-- :luafile does not split trailing | commands. Keep failure handling in Lua
-- so startup/test errors cannot be hidden by a later successful :qa!.
local ok, err = xpcall(function()
	assert(vim.v.errmsg == "", "startup error: " .. vim.v.errmsg)
	local test = assert(vim.env.NVIM_TEST_FILE, "NVIM_TEST_FILE is required")
	if test:match("/completion.lua$") or test:match("/lua_workspace.lua$") or test:match("/integration.lua$") then
		vim.api.nvim_exec_autocmds("BufReadPre", {})
		if test:match("/lua_workspace.lua$") then
			require("lz.n").trigger_load("lazydev.nvim")
		end
	end
	dofile(test)
	vim.wait(50, function()
		return vim.g.mayon_load_error ~= nil
	end, 10)
	assert(not vim.g.mayon_load_error, vim.g.mayon_load_error)
end, debug.traceback)
if not ok then
	io.stderr:write(tostring(err) .. "\n")
	vim.cmd("cquit 1")
end
vim.cmd("qa!")
