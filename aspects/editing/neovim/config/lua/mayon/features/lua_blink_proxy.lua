-- Blink health enumerates all configured providers, including inactive filetypes.
-- Exposing a local factory keeps the Lua-only optional module out of startup.
local M = {}
function M.new(...)
	require("lz.n").trigger_load("lazydev.nvim")
	return require("lazydev.integrations.blink").new(...)
end
return M
