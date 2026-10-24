local completion = require("mayon.features.native_completion")

local maps = vim.api.nvim_get_keymap("i")
local found = {}
for _, map in ipairs(maps) do
	if map.lhs == "<Tab>" then
		found.tab = map
	elseif map.lhs == "<S-Tab>" then
		found.shift_tab = map
	elseif map.lhs == "<C-Space>" then
		found.manual = map
	elseif map.lhs == "<CR>" then
		found.enter = map
	elseif map.lhs == "<Esc>" then
		found.escape = map
	end
end
assert(
	found.tab and found.shift_tab and found.manual and found.enter and found.escape,
	"native completion maps should be installed"
)

local ai = require("mayon.features.ai_completion")
local old_accept = ai.accept
local old_dismiss = ai.dismiss
local old_active, old_jump = vim.snippet.active, vim.snippet.jump
local old_pumvisible = vim.fn.pumvisible
local calls = {}
ai.accept = function()
	calls.ai = (calls.ai or 0) + 1
	return true
end
vim.snippet.active = function()
	calls.snippet_check = (calls.snippet_check or 0) + 1
	return true
end
vim.snippet.jump = function(direction)
	calls.jump = direction
end
assert(found.tab.callback() == "", "Tab should consume an available AI completion")
assert(calls.ai == 1 and not calls.snippet_check, "AI acceptance must outrank snippet navigation")

ai.accept = function()
	calls.ai = calls.ai + 1
	return false
end
assert(
	found.tab.callback() == "<Cmd>lua vim.snippet.jump(1)<CR>",
	"Tab should defer an active snippet jump until after its expression mapping"
)
assert(calls.snippet_check == 1, "snippet navigation should follow AI acceptance")
assert(
	found.shift_tab.callback() == "<Cmd>lua vim.snippet.jump(-1)<CR>",
	"Shift-Tab should defer reverse snippet navigation"
)

vim.fn.pumvisible = function()
	return 1
end
local previous_ai_calls = calls.ai
assert(
	found.tab.callback() == "<Cmd>lua vim.snippet.jump(1)<CR>",
	"Tab in the native popup should preserve snippet navigation"
)
assert(calls.ai == previous_ai_calls, "Tab in the native popup must not accept an AI suggestion")
vim.fn.pumvisible = old_pumvisible
ai.dismiss = function()
	return true
end
assert(found.escape.callback() == "", "Esc should dismiss a visible AI suggestion without leaving insert mode")
ai.dismiss = function()
	return false
end
assert(
	found.escape.callback() == vim.api.nvim_replace_termcodes("<Esc>", true, false, true),
	"Esc should retain its insert-mode exit behavior when no AI suggestion is visible"
)
ai.dismiss = old_dismiss

vim.snippet.active = function()
	return false
end
assert(found.tab.callback() == "<Tab>", "Tab should fall back to native indentation")
assert(completion.enter(true, -1) == "<CR>", "Enter with no selected item should insert a newline")
assert(completion.enter(true, 0) == "<C-y>", "Enter should accept an explicitly selected item")
assert(completion.enter(false, -1) == "<CR>", "Enter without a completion menu should insert a newline")
vim.snippet.active, vim.snippet.jump = old_active, old_jump

local snippets = completion.snippet_complete(0, "for")
assert(type(snippets) == "table", "C++ completefunc should return completion items")
local forr
for _, item in ipairs(snippets) do
	if item.word == "forr" then
		forr = item
		break
	end
end
assert(
	forr and forr.user_data and forr.info:find("for (int", 1, true),
	"C++ source should expose repository forr snippet"
)
assert(completion.snippet_complete(1, "") >= 0, "C++ completefunc should provide a valid findstart column")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.snippet.expand(forr.info)
assert(
	vim.api.nvim_get_current_line():find("for (int i = 0; i < n; i++) {", 1, true),
	"native snippet engine should expand repository C++ snippet"
)
assert(vim.snippet.active(), "expanded C++ snippet should expose native tabstops")
local previous_error = vim.v.errmsg
vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("i<Tab><S-Tab>", true, false, true), "xt", false)
assert(vim.v.errmsg == previous_error, "Tab and Shift-Tab snippet jumps should not raise expression-map errors")
assert(vim.snippet.active(), "snippet navigation should preserve the active snippet")
vim.snippet.stop()

local original_enable = vim.lsp.completion.enable
local enabled
vim.lsp.completion.enable = function(on, client_id, buf, opts)
	enabled = { on = on, client_id = client_id, buf = buf, opts = opts }
end
completion.attach({
	id = 12,
	supports_method = function(_, method, buf)
		return method == "textDocument/completion" and buf == vim.api.nvim_get_current_buf()
	end,
}, vim.api.nvim_get_current_buf())
assert(
	enabled and enabled.on and enabled.client_id == 12 and enabled.opts.autotrigger,
	"LSP attach should enable autotrigger completion"
)
assert(enabled.opts.convert == completion.convert, "LSP attach should register native item conversion")
vim.lsp.completion.enable = original_enable

local converted = completion.convert({
	label = "vector",
	kind = vim.lsp.protocol.CompletionItemKind.Class,
	detail = "std::vector<T>",
})
assert(
	converted.abbr == "vector" and converted.kind == require("mayon.kinds").Class,
	"LSP completion should put its kind icon in the leading column"
)
assert(converted.menu == "std::vector<T>", "LSP completion should include concise detail")

ai.accept = old_accept
io.stdout:write("Native LSP completion, Tab priority, Enter noselect, and C++ snippets passed\n")

-- InsertEnter also loads autopairs: test the final effective mapping, including
-- selected and unselected popup items, rather than only the mapping callback.
vim.snippet.stop()
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.api.nvim_feedkeys(vim.keycode('ia<Cmd>lua vim.fn.complete(1, {"abc", "abd"})<CR><C-n><CR><Esc>'), "xt", false)
assert(
	vim.api.nvim_buf_line_count(0) == 1 and vim.api.nvim_get_current_line() == "abc",
	"Enter should confirm selected item without newline after autopairs loads"
)
vim.wait(10)
assert(
	vim.lsp.inline_completion.is_enabled({ bufnr = 0 }),
	"closed completion popup must restore Copilot inline completion"
)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.api.nvim_feedkeys(vim.keycode('ia<Cmd>lua vim.fn.complete(1, {"abc", "abd"})<CR><CR><Esc>'), "xt", false)
assert(
	vim.api.nvim_buf_line_count(0) == 2 and vim.api.nvim_buf_get_lines(0, 0, 1, false)[1] == "a",
	"Enter should insert newline when no candidate is selected"
)
assert(vim.v.errmsg == "", vim.v.errmsg)
