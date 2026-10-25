local ui = require("mayon.features.completion_ui")
ui.setup()
ui.setup()
assert(#vim.api.nvim_get_autocmds({ group = "MayonCompletionUI", event = "CompleteChanged" }) == 1)
local original_info, original_pum = vim.fn.complete_info, vim.fn.pumvisible
local visible, preview = true, nil
vim.fn.pumvisible = function()
	return visible and 1 or 0
end
vim.fn.complete_info = function(fields)
	assert(fields == nil, "Neovim 0.12 preview_winid is available only in the unfiltered complete_info result")
	return { preview_winid = preview }
end
-- A slow resolve must still be decorated beyond the old 200ms timeout.
vim.api.nvim_exec_autocmds("CompleteChanged", {})
vim.wait(260)
local buf = vim.api.nvim_create_buf(false, true)
local lines = { "```lua", "function example(value)", "```" }
for n = 1, 50 do
	lines[#lines + 1] = "Documentation line " .. n
end
vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
preview = vim.api.nvim_open_win(buf, false, {
	relative = "editor",
	row = 2,
	col = 3,
	width = 40,
	height = 18,
	style = "minimal",
})
assert(vim.wait(250, function()
	return vim.bo[buf].filetype == "markdown"
end))
assert(vim.api.nvim_win_get_height(preview) <= 14)
assert(vim.wo[preview].showbreak == "NONE", "completion docs must override Markdown continuation arrows")
assert(vim.api.nvim_win_get_config(preview).title[1][1] == " Documentation ")
local view_before = vim.api.nvim_win_call(preview, vim.fn.winsaveview)
assert(ui.scroll(1))
local view_after = vim.api.nvim_win_call(preview, vim.fn.winsaveview)
assert(view_after.topline > view_before.topline, "Ctrl-f must scroll actual document content")
assert(ui.scroll(-1))
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), lines), "styling must preserve LSP text")
visible = false
assert(ui.scroll(1) == false, "no documentation must preserve native Ctrl-f fallback")
vim.api.nvim_exec_autocmds("CompleteDone", {})
-- Core owns its document; our lifecycle cleanup must not close unrelated floats.
assert(vim.api.nvim_win_is_valid(preview))
vim.api.nvim_win_close(preview, true)
vim.api.nvim_buf_delete(buf, { force = true })
vim.fn.complete_info, vim.fn.pumvisible = original_info, original_pum

local old_clients = vim.lsp.get_clients
local old_mode = vim.api.nvim_get_mode
local original_open = vim.lsp.util.open_floating_preview
local requests, opened = {}, 0
local signature_lines
local fake = {
	offset_encoding = "utf-16",
	server_capabilities = { signatureHelpProvider = { triggerCharacters = { "(" }, retriggerCharacters = { "," } } },
	requests = {},
}
function fake:request(method, params, callback)
	assert(method == "textDocument/signatureHelp")
	requests[#requests + 1] = { callback = callback, params = params }
	return true, #requests
end
vim.lsp.get_clients = function(filter)
	if filter and filter.method == "textDocument/signatureHelp" then
		return { fake }
	end
	return old_clients(filter)
end
vim.api.nvim_get_mode = function()
	return { mode = "i" }
end
local owned
vim.lsp.util.open_floating_preview = function(lines)
	signature_lines = lines
	opened = opened + 1
	local b = vim.api.nvim_create_buf(false, true)
	owned = vim.api.nvim_open_win(
		b,
		false,
		{ relative = "editor", row = 2, col = 2, width = 20, height = 2, style = "minimal" }
	)
	return b, owned
end
local insert = vim.api.nvim_get_autocmds({ group = "MayonCompletionUI", event = "TextChangedI" })[1].callback
local function type_trigger(char)
	char = char or "("
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "example" .. char .. " " })
	vim.api.nvim_win_set_cursor(0, { 1, 7 + #char })
	insert({ buf = vim.api.nvim_get_current_buf() })
end
local result = { signatures = { { label = "example(value)", documentation = "Verbose function documentation" } } }
type_trigger()
assert(vim.wait(400, function()
	return #requests == 1
end))
assert(requests[1].params.context.triggerCharacter == "(")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "changed while waiting" })
requests[1].callback(nil, result)
assert(opened == 0, "signature with a stale changedtick must not appear")
type_trigger()
assert(vim.wait(400, function()
	return #requests == 2
end))
requests[2].callback(nil, result)
assert(opened == 1 and vim.api.nvim_win_is_valid(owned), "current server trigger should show signature")
assert(not table.concat(signature_lines, "\n"):find("Verbose", 1, true), "automatic signatures should stay compact")
assert(
	result.signatures[1].documentation == "Verbose function documentation",
	"compact rendering must not mutate the LSP response"
)
type_trigger("a")
vim.wait(180)
assert(#requests == 2, "normal argument text must not issue a signature request")
type_trigger(",")
assert(vim.wait(400, function()
	return #requests == 3
end))
assert(requests[3].params.context.isRetrigger, "retrigger session must survive argument text and closed display")
requests[3].callback(nil, result)
local unrelated_buf = vim.api.nvim_create_buf(false, true)
local unrelated = vim.api.nvim_open_win(
	unrelated_buf,
	false,
	{ relative = "editor", row = 5, col = 2, width = 20, height = 2, style = "minimal" }
)
vim.api.nvim_exec_autocmds("InsertLeave", {})
assert(not vim.api.nvim_win_is_valid(owned), "InsertLeave closes the signature we own")
assert(vim.api.nvim_win_is_valid(unrelated), "cleanup must preserve another feature's window")
type_trigger()
assert(vim.wait(400, function()
	return #requests == 4
end))
vim.api.nvim_exec_autocmds("BufLeave", {})
requests[4].callback(nil, result)
assert(opened == 2, "late response after leaving buffer must not reopen signature")
vim.fn.pumvisible = function()
	return 1
end
type_trigger()
vim.wait(220)
assert(#requests == 4, "signature must not compete with visible completion docs")
vim.api.nvim_win_close(unrelated, true)
vim.api.nvim_buf_delete(unrelated_buf, { force = true })
vim.fn.pumvisible = original_pum
vim.lsp.get_clients = old_clients
vim.api.nvim_get_mode = old_mode
vim.lsp.util.open_floating_preview = original_open
