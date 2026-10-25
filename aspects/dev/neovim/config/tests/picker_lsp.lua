-- Real Neovim Client:request and a local in-process LSP. No network/server binary.
require("mayon.features.ai_completion").set("off")
vim.api.nvim_exec_autocmds("User", { pattern = "MayonVeryLazy" })
vim.o.columns, vim.o.lines = 160, 50
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local path = root .. "/symbols.txt"
local lines = {}
for i = 1, 250 do
	lines[i] = "symbol_" .. i
end
vim.fn.writefile(lines, path)
vim.cmd.edit(path)
vim.lsp.enable("copilot", false)
local cancelled, replies, delay = {}, 0, 5
local client_id = vim.lsp.start({
	name = "r28-picker-fixture",
	root_dir = root,
	cmd = function(dispatch)
		local seq, closing = 0, false
		return {
			request = function(method, params, cb, on_reply)
				seq = seq + 1
				local id, result = seq, nil
				if method == "initialize" then
					result = {
						capabilities = {
							documentSymbolProvider = true,
							workspaceSymbolProvider = true,
							definitionProvider = true,
							referencesProvider = true,
							typeDefinitionProvider = true,
							implementationProvider = true,
							declarationProvider = true,
							callHierarchyProvider = true,
						},
					}
				elseif method:find("Symbol") or method == "workspace/symbol" then
					result = {}
					for i = 1, 250 do
						result[i] = {
							name = "symbol_" .. i,
							kind = 12,
							location = {
								uri = vim.uri_from_fname(path),
								range = {
									start = { line = i - 1, character = 0 },
									["end"] = { line = i - 1, character = 8 },
								},
							},
						}
					end
				elseif method == "textDocument/prepareCallHierarchy" then
					result = {
						{
							name = "entry",
							kind = 12,
							uri = vim.uri_from_fname(path),
							range = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 8 } },
							selectionRange = {
								start = { line = 0, character = 0 },
								["end"] = { line = 0, character = 8 },
							},
						},
					}
				elseif method:find("callHierarchy/") then
					result = {}
					for i = 1, 250 do
						local range =
							{ start = { line = i - 1, character = 0 }, ["end"] = { line = i - 1, character = 8 } }
						local item = {
							name = "symbol_" .. i,
							kind = 12,
							uri = vim.uri_from_fname(path),
							range = range,
							selectionRange = range,
						}
						result[i] = { from = item, to = item, fromRanges = { range } }
					end
				elseif method ~= "shutdown" then
					result = {}
					for i = 1, 250 do
						result[i] = {
							uri = vim.uri_from_fname(path),
							range = {
								start = { line = i - 1, character = 0 },
								["end"] = { line = i - 1, character = 8 },
							},
						}
					end
				end
				vim.defer_fn(function()
					replies = replies + 1
					if on_reply then
						on_reply(id)
					end
					cb(nil, result)
				end, method == "initialize" and 0 or delay)
				return true, id
			end,
			notify = function(method, params)
				if method == "$/cancelRequest" then
					cancelled[params.id] = true
				elseif method == "exit" then
					closing = true
					dispatch.on_exit(0, 0)
				end
				return true
			end,
			is_closing = function()
				return closing
			end,
			terminate = function()
				closing = true
				dispatch.on_exit(0, 0)
			end,
		}
	end,
})
assert(vim.wait(1000, function()
	local c = vim.lsp.get_client_by_id(client_id)
	return c and c.initialized
end))
local errors = {}
local notify = vim.notify
vim.notify = function(msg, level, opts)
	if level == vim.log.levels.ERROR then
		errors[#errors + 1] = tostring(msg)
	end
	return notify(msg, level, opts)
end
local function slow(item)
	-- Force the real 1ms finder budget to expire; the first files item initializes
	-- its yielder on the coroutine before the delayed LSP response reaches it.
	local start = vim.uv.hrtime()
	while vim.uv.hrtime() - start < 30000 do
	end
	return item
end
for _, source in ipairs({
	"lsp_workspace_symbols",
	"lsp_symbols",
	"lsp_definitions",
	"lsp_references",
	"lsp_type_definitions",
	"lsp_implementations",
	"lsp_declarations",
	"lsp_incoming_calls",
	"lsp_outgoing_calls",
}) do
	vim.api.nvim_set_current_buf(vim.fn.bufnr(path))
	local picker = Snacks.picker({
		multi = { "files", source },
		cwd = root,
		transform = slow,
		filter = { default = true },
		include_current = true,
		jump = { single = false },
		show_delay = 0,
	})
	assert(
		vim.wait(3000, function()
			return #picker.finder.items >= 251 and not picker:is_active() or #errors > 0 or vim.v.errmsg ~= ""
		end),
		source .. " timed out"
	)
	assert(vim.v.errmsg == "" and #errors == 0, source .. ": " .. vim.v.errmsg .. table.concat(errors, "\n"))
	assert(#picker.finder.items >= 251, source .. " lost LSP results")
	picker:close()
	vim.wait(20)
end
-- Closing cancels keyed client/request IDs and ignores late responses.
delay = 150
vim.api.nvim_set_current_buf(vim.fn.bufnr(path))
local picker = Snacks.picker.lsp_workspace_symbols({ filter = { default = true } })
assert(vim.wait(500, function()
	return next(vim.lsp.get_client_by_id(client_id).requests) ~= nil
end))
picker:close()
assert(
	vim.wait(1000, function()
		return next(cancelled) ~= nil
	end),
	"closed picker did not cancel its LSP request"
)
vim.wait(250)
assert(#errors == 0 and vim.v.errmsg == "", table.concat(errors, "\n") .. vim.v.errmsg)
vim.notify = notify
vim.lsp.get_client_by_id(client_id):stop(true)
vim.fn.delete(root, "rf")
print("LSP coroutine delivery, nine multi-source pickers and cancel/late-response passed")
