local capture = assert(_G.MayonSelfcheck)
capture.phase = "startup:" .. assert(vim.env.NVIM_STARTUP_CASE)
capture.hook_notify()
vim.api.nvim_exec_autocmds("UIEnter", {})
vim.wait(150)
local kind = vim.env.NVIM_STARTUP_CASE
if kind == "file" or kind == "session-save" then
	assert(vim.bo.filetype == "c", "file argv lost C filetype")
	assert(vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()], "file argv lost parser")
	if kind == "session-save" then
		local sessions = require("mayon.features.sessions")
		sessions.setup()
		assert(sessions.save(true))
	end
elseif kind == "session-restore" then
	local sessions = require("mayon.features.sessions")
	sessions.setup()
	sessions.auto_restore()
	assert(vim.api.nvim_buf_get_name(0):match("/main.c$"), "fresh process did not restore document")
	assert(#vim.api.nvim_list_tabpages() == 1, "session left an empty tab")
elseif kind == "pipe" then
	assert(vim.api.nvim_get_current_line() == "pipe fixture", "stdin was lost or session replaced it")
elseif kind == "help" then
	assert(vim.bo.buftype == "help", "help argv did not open help")
	assert(#vim.lsp.get_clients({ bufnr = 0, name = "copilot" }) == 0, "Copilot attached to help")
elseif kind == "directory" then
	assert(#Snacks.picker.get({ source = "explorer" }) > 0, "directory startup did not open Project tree")
else
	assert(vim.api.nvim_buf_get_name(0) == "", "empty startup unexpectedly restored a file")
end
assert(#capture.finish() == 0, vim.inspect(capture.events))
print("startup passed: " .. kind)
