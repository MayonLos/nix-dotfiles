-- Run with isolated XDG directories: nvim --clean --headless -l config/nvim/tests/breadcrumbs.lua
local root = vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)))
vim.opt.rtp:prepend(root)
local api, base = vim.api, vim.fn.tempname()
vim.fn.mkdir(base, "p")
local old_clients = vim.lsp.get_clients
local clients, requests = {}, {}
vim.lsp.get_clients = function(opts)
	if opts and opts.bufnr then
		return clients
	end
	return clients
end
local client
client = {
	id = 7,
	offset_encoding = "utf-16",
	attached_buffers = {},
	supports_method = function(_, method, bufnr)
		assert(type(bufnr) == "number", "supports_method must receive the native buffer number")
		return method == "textDocument/documentSymbol"
	end,
	request = function(self, method, params, callback, buf)
		assert(self == client, "request must receive its LSP client as self")
		assert(method == "textDocument/documentSymbol")
		assert(params.textDocument.uri == vim.uri_from_bufnr(buf), "request must use textDocument params")
		requests[#requests + 1] = { callback = callback, buf = buf, uri = params.textDocument.uri }
		return true, #requests
	end,
	cancel_request = function() end,
}
local function await_request(index)
	assert(
		vim.wait(800, function()
			return requests[index] ~= nil
		end),
		"debounced documentSymbol request should be sent"
	)
	return requests[index]
end
local function respond(request, result, err)
	request.callback(err, result)
	vim.wait(50, function()
		return false
	end)
end

local ok, err = xpcall(function()
	local file = base .. "/symbols.lua"
	vim.fn.writefile({ "local 猫 = function() end", "local sibling = 1" }, file)
	vim.cmd.edit(vim.fn.fnameescape(file))
	local buf = api.nvim_get_current_buf()
	clients = { client }
	client.attached_buffers[buf] = true
	local breadcrumbs = require("mayon.breadcrumbs")
	assert(breadcrumbs.setup() == nil)
	assert(breadcrumbs.setup() == nil, "setup must be idempotent")
	api.nvim_exec_autocmds("LspAttach", { buffer = buf, data = { client_id = client.id } })
	local req = await_request(1)
	respond(req, {
		{
			name = "outer",
			kind = 5,
			range = { start = { line = 0, character = 0 }, ["end"] = { line = 1, character = 17 } },
			selectionRange = { start = { line = 0, character = 0 }, ["end"] = { line = 0, character = 5 } },
			children = {
				{
					name = "猫",
					kind = 12,
					range = { start = { line = 0, character = 6 }, ["end"] = { line = 0, character = 20 } },
					children = {},
				},
			},
		},
	})
	local path = breadcrumbs.get(buf, { row = 0, col = 13 })
	assert(
		#path == 2 and path[1].name == "outer" and path[2].name == "猫",
		"nested symbols should produce containing path: " .. vim.inspect(path)
	)
	assert(
		path[1].kind == "Class" and path[1].icon == require("mayon.kinds").Class .. " ",
		"kind names and shared glyphs should resolve"
	)
	assert(
		#breadcrumbs.get(buf, { row = 1, col = 3 }) == 1,
		"position lookup should reuse cached symbols for a sibling"
	)
	assert(#breadcrumbs.get(buf, { row = 1, col = 17 }) == 0, "symbol range end is exclusive")

	-- UTF-16 protocol character 6 follows the three-byte 猫 plus preceding ASCII.
	local bytes = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
	assert(bytes:sub(1, 11) == "local 猫 =", "test line should contain multibyte text")
	assert(#breadcrumbs.get(buf, { row = 0, col = 12 }) == 2, "UTF-16 ranges should map to byte columns")

	-- Flat SymbolInformation ranges are ordered by containment and use containerName as a fallback.
	api.nvim_exec_autocmds("TextChanged", { buffer = buf })
	local flat = await_request(2)
	respond(flat, {
		{
			name = "inner",
			kind = 12,
			containerName = "Namespace",
			location = { range = { start = { line = 0, character = 6 }, ["end"] = { line = 0, character = 20 } } },
		},
		{
			name = "outer",
			kind = 5,
			location = { range = { start = { line = 0, character = 0 }, ["end"] = { line = 1, character = 20 } } },
		},
	})
	path = breadcrumbs.get(buf, { row = 0, col = 13 })
	assert(
		#path == 3 and path[1].name == "outer" and path[2].name == "Namespace" and path[3].name == "inner",
		"flat symbols should form a containment path"
	)

	-- A newer edit invalidates an older response even if its callback arrives later.
	api.nvim_exec_autocmds("TextChanged", { buffer = buf })
	local old = await_request(3)
	api.nvim_buf_set_lines(buf, 0, 1, false, { "changed" })
	api.nvim_exec_autocmds("TextChanged", { buffer = buf })
	respond(old, {
		{
			name = "stale",
			kind = 12,
			range = { start = { line = 0, character = 0 }, ["end"] = { line = 1, character = 0 } },
		},
	})
	assert(#breadcrumbs.get(buf, { row = 0, col = 0 }) == 0, "stale callback must not populate cache")
	local fresh = await_request(4)
	respond(fresh, {
		{
			name = "fresh",
			kind = 12,
			range = { start = { line = 0, character = 0 }, ["end"] = { line = 1, character = 0 } },
		},
	})
	assert(breadcrumbs.get(buf, { row = 0, col = 0 })[1].name == "fresh", "current response should populate cache")

	-- Renaming invalidates old-URI responses and requests symbols for the new path.
	api.nvim_exec_autocmds("TextChanged", { buffer = buf })
	local old_uri_request = await_request(5)
	local renamed_path = base .. "/renamed.lua"
	vim.b[buf].mayon_original_buftype = ""
	vim.bo[buf].buftype = "acwrite"
	api.nvim_buf_set_name(buf, renamed_path)
	respond(old_uri_request, {
		{
			name = "old_uri",
			kind = 12,
			location = {
				uri = old_uri_request.uri,
				range = { start = { line = 0, character = 0 }, ["end"] = { line = 1, character = 0 } },
			},
		},
	})
	assert(#breadcrumbs.get(buf, { row = 0, col = 0 }) == 0, "old-URI response must not populate cache after rename")
	api.nvim_exec_autocmds("BufFilePost", { buffer = buf })
	local renamed_request = await_request(6)
	local renamed_uri = vim.uri_from_bufnr(buf)
	assert(renamed_request.uri == renamed_uri, "rename event should request symbols using the new URI")
	respond(renamed_request, {
		{
			name = "renamed",
			kind = 12,
			location = {
				uri = renamed_uri,
				range = { start = { line = 0, character = 0 }, ["end"] = { line = 1, character = 0 } },
			},
		},
	})
	assert(breadcrumbs.get(buf, { row = 0, col = 0 })[1].name == "renamed", "new-URI symbols should populate cache")

	-- Saving without changing lines still refreshes symbols and exits acwrite mode.
	vim.bo[buf].buftype = ""
	vim.b[buf].mayon_original_buftype = nil
	api.nvim_exec_autocmds("BufWritePost", { buffer = buf })
	local saved = await_request(7)
	respond(saved, {
		{
			name = "saved",
			kind = 12,
			range = { start = { line = 0, character = 0 }, ["end"] = { line = 1, character = 0 } },
		},
	})
	assert(
		breadcrumbs.get(buf, { row = 0, col = 0 })[1].name == "saved",
		"BufWritePost should refresh symbols without a text edit"
	)

	-- Buffer wipe must make late responses harmless and remove cached data.
	api.nvim_exec_autocmds("TextChanged", { buffer = buf })
	local late = await_request(8)
	vim.cmd("bwipeout! " .. buf)
	respond(late, {
		{
			name = "gone",
			kind = 12,
			range = { start = { line = 0, character = 0 }, ["end"] = { line = 1, character = 0 } },
		},
	})
	assert(#breadcrumbs.get(buf, { row = 0, col = 0 }) == 0, "wiped buffers should never expose cached paths")
end, debug.traceback)

vim.lsp.get_clients = old_clients
vim.fn.delete(base, "rf")
if not ok then
	io.stderr:write(err .. "\n")
	vim.cmd("cquit 1")
end
io.stdout:write("native LSP breadcrumb cache checks passed\n")
vim.cmd("qa!")
