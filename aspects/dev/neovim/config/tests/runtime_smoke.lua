-- Exercise native Neovim LSP user flows through a real Client and an in-process
-- transport. The fixture never starts a server process or accesses the network.
vim.cmd.packadd("nvim-lspconfig")
require("mayon.features.ai_completion").set("off")

local errors, deprecated, notices = {}, {}, {}
local original_notify = vim.notify
vim.notify = function(message, level, opts)
	local text = tostring(message)
	notices[#notices + 1] = { level = level, text = text }
	if level == vim.log.levels.ERROR then
		errors[#errors + 1] = text
	end
	if text:lower():find("deprecated", 1, true) then
		deprecated[#deprecated + 1] = text
	end
	return original_notify(message, level, opts)
end

local project = vim.fn.tempname()
vim.fn.mkdir(project, "p")
local path = project .. "/fixture.txt"
vim.fn.writefile({ "target();", "source();", "rename_me();", "action_me();", "tail();" }, path)
vim.cmd.edit(path)
local bufnr = vim.api.nvim_get_current_buf()
-- Leave the fixture unclassified so the configuration cannot auto-enable a
-- machine-installed language server while this test is running offline.
vim.bo[bufnr].filetype = "text"

local next_id, pending, closing, requested, callback_results = 0, {}, false, {}, {}
local responses = {
	["textDocument/definition"] = function()
		local range = { start = { line = 4, character = 0 }, ["end"] = { line = 4, character = 4 } }
		return { uri = vim.uri_from_fname(path), range = range }
	end,
	["textDocument/hover"] = function()
		return { contents = { kind = "markdown", value = "Fixture hover documentation" } }
	end,
	["textDocument/signatureHelp"] = function()
		return {
			signatures = { { label = "fixture(value: number)", documentation = "Fixture signature documentation" } },
			activeSignature = 0,
			activeParameter = 0,
		}
	end,
	["textDocument/rename"] = function()
		return {
			changes = {
				[vim.uri_from_fname(path)] = {
					{
						range = { start = { line = 2, character = 0 }, ["end"] = { line = 2, character = 9 } },
						newText = "renamed",
					},
				},
			},
		}
	end,
	["textDocument/codeAction"] = function()
		return {
			{
				title = "Fixture: apply code action",
				kind = "quickfix",
				edit = {
					changes = {
						[vim.uri_from_fname(path)] = {
							{
								range = { start = { line = 3, character = 0 }, ["end"] = { line = 3, character = 9 } },
								newText = "action_applied",
							},
						},
					},
				},
			},
		}
	end,
}

local client_id = vim.lsp.start({
	name = "runtime-smoke-fixture",
	root_dir = project,
	cmd = function(dispatch)
		return {
			request = function(method, _, callback, on_reply)
				requested[#requested + 1] = method
				next_id = next_id + 1
				local id = next_id
				pending[id] = true
				local result
				if method == "initialize" then
					result = {
						capabilities = {
							textDocumentSync = 1,
							definitionProvider = true,
							hoverProvider = true,
							signatureHelpProvider = { triggerCharacters = { "(" } },
							renameProvider = true,
							codeActionProvider = true,
						},
					}
				elseif responses[method] then
					result = responses[method]()
				end
				vim.defer_fn(function()
					pending[id] = nil
					if on_reply then
						on_reply(id)
					end
					if not closing then
						callback_results[#callback_results + 1] = { method = method, result = vim.deepcopy(result) }
						local ok, err = xpcall(function()
							callback(nil, result)
						end, debug.traceback)
						if not ok then
							errors[#errors + 1] = tostring(err)
						end
					end
				end, method == "initialize" and 0 or 5)
				return true, id
			end,
			notify = function(method)
				if method == "exit" then
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
assert(
	vim.wait(1000, function()
		local client = vim.lsp.get_client_by_id(client_id)
		return client and client.initialized
	end),
	"fixture LSP client did not initialize"
)

local lsp = require("mayon.lsp")
lsp.setup()
require("mayon.config.keymaps").setup()
vim.api.nvim_exec_autocmds("LspAttach", { buffer = bufnr, data = { client_id = client_id } })
vim.api.nvim_set_current_buf(bufnr)
assert(vim.api.nvim_buf_get_name(bufnr) == path, "fixture source buffer was not active after LSP attach")

local function mapping(lhs)
	local normalized = lhs:gsub("<leader>", vim.g.mapleader or "\\")
	for _, maps in ipairs({ vim.api.nvim_buf_get_keymap(bufnr, "n"), vim.api.nvim_get_keymap("n") }) do
		for _, map in ipairs(maps) do
			if map.lhs == lhs or map.lhs == normalized then
				return map
			end
		end
	end
	error("missing buffer LSP map: " .. lhs)
end

local function invoke(lhs)
	local map = mapping(lhs)
	assert(type(map.callback) == "function", lhs .. " should be a callback mapping")
	map.callback()
end

local function has_float_with(needle)
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local config = vim.api.nvim_win_get_config(win)
		if config.relative ~= "" then
			local text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false), "\n")
			if text:find(needle, 1, true) then
				return true, config
			end
		end
	end
	return false
end

vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.api.nvim_set_current_buf(bufnr)
invoke("gd")
assert(
	vim.wait(1000, function()
		return vim.api.nvim_win_get_cursor(0)[1] == 5
	end),
	"gd did not jump to the fixture definition; requests="
		.. vim.inspect(requested)
		.. "; responses="
		.. vim.inspect(callback_results)
		.. "; cursor="
		.. vim.inspect(vim.api.nvim_win_get_cursor(0))
		.. "; buf="
		.. vim.api.nvim_buf_get_name(0)
		.. "; bt="
		.. vim.bo.buftype
		.. "; qf="
		.. vim.inspect(vim.fn.getqflist())
		.. "; notices="
		.. vim.inspect(notices)
		.. "; buffers="
		.. vim.inspect(vim.tbl_map(function(b)
			return { b, vim.api.nvim_buf_get_name(b), vim.api.nvim_buf_is_loaded(b) }
		end, vim.api.nvim_list_bufs()))
		.. "; pending="
		.. vim.inspect(pending)
		.. "; errors="
		.. vim.inspect(errors)
		.. "; errmsg="
		.. vim.v.errmsg
)

vim.api.nvim_win_set_cursor(0, { 1, 0 })
invoke("K")
assert(
	vim.wait(1000, function()
		return has_float_with("Fixture hover documentation")
	end),
	"K did not show the fixture hover text"
)
local hover_ok, hover_config = has_float_with("Fixture hover documentation")
assert(
	hover_ok and hover_config.border[1] == "╭",
	"hover should use the rounded float border: " .. vim.inspect(hover_config.border)
)
for _, win in ipairs(vim.api.nvim_list_wins()) do
	if vim.api.nvim_win_get_config(win).relative ~= "" then
		vim.api.nvim_win_close(win, true)
	end
end

invoke("gK")
assert(
	vim.wait(1000, function()
		return has_float_with("fixture(value: number)")
	end),
	"gK did not show the fixture signature"
)
for _, win in ipairs(vim.api.nvim_list_wins()) do
	if vim.api.nvim_win_get_config(win).relative ~= "" then
		vim.api.nvim_win_close(win, true)
	end
end

local original_input = vim.ui.input
vim.ui.input = function(_, callback)
	callback("renamed")
end
vim.api.nvim_win_set_cursor(0, { 3, 0 })
invoke("<leader>cr")
vim.ui.input = original_input
assert(
	vim.wait(1000, function()
		return vim.api.nvim_buf_get_lines(bufnr, 2, 3, false)[1] == "renamed();"
	end),
	"rename did not apply the workspace edit"
)

local original_select = vim.ui.select
local selected_action, selection_items
vim.ui.select = function(items, _, callback)
	selection_items = vim.deepcopy(items)
	for _, item in ipairs(items) do
		if item.action and item.action.title == "Fixture: apply code action" then
			selected_action = item
			callback(item)
			return
		end
	end
	callback(nil)
end
vim.api.nvim_win_set_cursor(0, { 4, 0 })
invoke("<leader>ca")
assert(
	vim.wait(1000, function()
		return selected_action ~= nil or #notices > 0
	end),
	"code action response timed out"
)
vim.ui.select = original_select
assert(
	selected_action,
	"code action picker omitted the fixture action: requests="
		.. vim.inspect(requested)
		.. "; items="
		.. vim.inspect(selection_items)
		.. "; notices="
		.. vim.inspect(notices)
)
assert(
	vim.wait(1000, function()
		return vim.api.nvim_buf_get_lines(bufnr, 3, 4, false)[1] == "action_applied();"
	end),
	"selected code action did not apply its edit"
)

local ns = vim.api.nvim_create_namespace("runtime-smoke-diagnostics")
vim.diagnostic.set(ns, bufnr, {
	{
		lnum = 1,
		col = 0,
		message = "Fixture diagnostic message",
		severity = vim.diagnostic.severity.ERROR,
		source = "fixture",
	},
})
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.diagnostic.open_float(0)
local diagnostic_float_ok, diagnostic_float = has_float_with("Fixture diagnostic message")
assert(diagnostic_float_ok, "diagnostic float omitted the published diagnostic")
assert(
	diagnostic_float.border[1] == "╭",
	"diagnostic float should use the rounded border: " .. vim.inspect(diagnostic_float.border)
)
vim.diagnostic.setqflist({ open = true, title = "Fixture diagnostics", namespace = ns })
assert(
	vim.wait(1000, function()
		return vim.bo.buftype == "quickfix" and #vim.fn.getqflist() == 1
	end),
	"diagnostic quickfix list was not populated"
)
assert(vim.fn.getqflist()[1].text:find("Fixture diagnostic message", 1, true), "quickfix entry lost diagnostic text")

vim.wait(50)
local messages = vim.api.nvim_exec2("messages", { output = true }).output
local suspicious_messages = {}
for line in messages:gmatch("[^\n]+") do
	local lowered = line:lower()
	if lowered:find("error", 1, true) or lowered:find("deprecated", 1, true) then
		suspicious_messages[#suspicious_messages + 1] = line
	end
end
assert(#errors == 0, "vim.notify ERROR: " .. table.concat(errors, "\n"))
assert(#deprecated == 0, "deprecated notification: " .. table.concat(deprecated, "\n"))
assert(#suspicious_messages == 0, ":messages error/deprecated: " .. table.concat(suspicious_messages, "\n"))
assert(vim.v.errmsg == "", "v:errmsg: " .. vim.v.errmsg)

vim.notify = original_notify
vim.lsp.get_client_by_id(client_id):stop(true)
vim.fn.delete(project, "rf")
print(
	"runtime LSP smoke passed: gd, hover, signature, rename, code action, diagnostic float and quickfix; no errors/deprecations"
)
