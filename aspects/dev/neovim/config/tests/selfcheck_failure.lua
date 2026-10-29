-- The Nix check expects this process to fail, and checks the failure marker.
local capture = assert(_G.MayonSelfcheck)
vim.notify("selfcheck injected notification", vim.log.levels.ERROR)
vim.api.nvim_echo({ { "selfcheck injected echo", "ErrorMsg" } }, true, { err = true })
vim.schedule(function()
	error("selfcheck injected callback")
end)
vim.lsp.log.error("selfcheck injected LSP error")
vim.lsp.log.error("rpc", "clangd", "stderr", "error: compiler process crashed")
vim.lsp.log.error("rpc", "clangd", "stderr", "12:00:00.000 error: compiler process crashed")
vim.wait(100)
local errors = capture.finish(true)
local sources = {}
for _, event in ipairs(errors) do
	sources[event.source] = true
end
assert(sources.notify or sources["snacks.notifier"], "notify observer failed")
assert(sources.echo, "echo observer failed")
assert(sources.lua_callback, "scheduled callback observer failed")
assert(sources["lsp.log"], "LSP log observer failed")
assert(
	vim.iter(errors):any(function(event)
		return event.source == "lsp.log" and event.message:find("compiler process crashed", 1, true)
	end),
	"unknown/lowercase server stderr was incorrectly ignored"
)
assert(
	vim.iter(errors):any(function(event)
		return event.source == "lsp.log" and event.message:find("12:00:00.000", 1, true)
	end),
	"timestamped server stderr was incorrectly ignored"
)
vim.v.errmsg = "" -- Exercise capture-based rejection, independent of v:errmsg.
print("SELFCHECK_INJECTION_OBSERVED")
-- run.lua must reject the captured ERRORs even after this file returns.
