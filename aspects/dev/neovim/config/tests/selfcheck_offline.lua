-- Test-only Copilot transport, installed before VIMINIT. The real configuration,
-- attach callbacks and completion handlers run without credentials or a server.
local function install(rpc)
	local start = rpc.start
	rpc.start = function(cmd, dispatch, opts)
		if type(cmd) ~= "table" or not tostring(cmd[1]):find("copilot-language-server", 1, true) then
			return start(cmd, dispatch, opts)
		end
		local closed, seq = false, 0
		return {
			request = function(method, _, callback, on_reply)
				seq = seq + 1
				local id, result = seq, nil
				if method == "initialize" then
					result = {
						capabilities = { textDocumentSync = 1, inlineCompletionProvider = true },
						serverInfo = { name = "offline-copilot-fixture" },
					}
				elseif method == "textDocument/inlineCompletion" then
					result = { items = { { insertText = "offline_fixture", filterText = "offline_fixture" } } }
				end
				vim.schedule(function()
					if not closed then
						if on_reply then
							on_reply(id)
						end
						callback(nil, result, id)
					end
				end)
				return true, id
			end,
			notify = function(method)
				if method == "exit" and not closed then
					closed = true
					dispatch.on_exit(0, 0)
				end
				return true
			end,
			is_closing = function()
				return closed
			end,
			terminate = function()
				if not closed then
					closed = true
					dispatch.on_exit(0, 0)
				end
			end,
		}
	end
end
-- Keep the cold-start contract: observing a future RPC transport must not load
-- vim.lsp before a document needs it.
local require_module = require
local installed = {}
_G.require = function(name)
	local module = require_module(name)
	if name == "vim.lsp.rpc" and not installed[module] then
		installed[module] = true
		install(module)
	end
	return module
end
if package.loaded["vim.lsp.rpc"] then
	local rpc = package.loaded["vim.lsp.rpc"]
	installed[rpc] = true
	install(rpc)
end
