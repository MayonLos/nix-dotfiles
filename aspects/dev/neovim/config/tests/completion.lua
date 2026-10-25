local completion = require("mayon.features.native_completion")
if vim.env.NVIM_EXPECTED_CONFIG_DIR then
	local source = debug.getinfo(completion.setup, "S").source:sub(2)
	local expected = vim.fs.normalize(vim.env.NVIM_EXPECTED_CONFIG_DIR) .. "/"
	assert(
		vim.startswith(vim.fs.normalize(source), expected),
		"completion test loaded a config outside the expected worktree"
	)
end
completion.setup()
assert(vim.o.pumborder == "none" and vim.o.pumblend == 0, "native completion should use an opaque borderless menu")

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

-- Use a deterministic in-process LSP client to verify ordinary typing reaches
-- the native completion menu without contacting Copilot or another service.
require("mayon.features.ai_completion").set("off")
vim.lsp.enable("lua_ls", false)
local fixture_requests, fixture_closing = {}, false
local fixture_id = vim.lsp.start({
	name = "native-completion-fixture",
	root_dir = vim.fn.getcwd(),
	cmd = function(dispatch)
		return {
			request = function(method, params, callback, on_reply)
				fixture_requests[#fixture_requests + 1] = { method = method, params = params }
				local id = #fixture_requests
				local result
				if method == "initialize" then
					result = {
						capabilities = {
							textDocumentSync = 1,
							completionProvider = { triggerCharacters = { "." } },
						},
					}
				elseif method == "textDocument/completion" then
					result = { { label = "vector", kind = vim.lsp.protocol.CompletionItemKind.Variable } }
				end
				vim.defer_fn(function()
					if on_reply then
						on_reply(id)
					end
					if not fixture_closing then
						callback(nil, result)
					end
				end, method == "initialize" and 0 or 5)
				return true, id
			end,
			notify = function(method)
				if method == "exit" then
					fixture_closing = true
					dispatch.on_exit(0, 0)
				end
				return true
			end,
			is_closing = function()
				return fixture_closing
			end,
			terminate = function()
				fixture_closing = true
				dispatch.on_exit(0, 0)
			end,
		}
	end,
})
assert(
	vim.wait(1000, function()
		local client = vim.lsp.get_client_by_id(fixture_id)
		return client and client.initialized
	end),
	"completion fixture LSP did not initialize"
)
local completion_buf = vim.api.nvim_get_current_buf()
vim.bo[completion_buf].filetype = "lua"
vim.api.nvim_exec_autocmds("LspAttach", { buffer = completion_buf, data = { client_id = fixture_id } })
vim.cmd("syntax on")
vim.treesitter.start(completion_buf, "lua")
vim.api.nvim_buf_set_lines(completion_buf, 0, -1, false, { "" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.o.completeopt = "menuone,noselect,popup"
local automatic_menu_opened = false
vim.defer_fn(function()
	vim.api.nvim_feedkeys("c", "n", false)
end, 50)
vim.defer_fn(function()
	automatic_menu_opened = vim.fn.pumvisible() == 1
	if automatic_menu_opened then
		vim.api.nvim_feedkeys(vim.keycode("<C-n><C-y>"), "n", false)
	end
	vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "n", false)
end, 350)
vim.api.nvim_feedkeys(vim.keycode("ive"), "xt!", false)
assert(automatic_menu_opened, "typing an ordinary Lua identifier should open the native LSP completion menu")
local automatic_requests = vim.tbl_filter(function(request)
	return request.method == "textDocument/completion"
end, fixture_requests)
assert(#automatic_requests == 1, "debounced ordinary typing should send one LSP request")
assert(automatic_requests[1].params.position.character == 3, "debounced typing should request at the latest cursor")
assert(
	vim.api.nvim_get_current_line() == "vector",
	"selected native LSP completion should be accepted; line=" .. vim.inspect(vim.api.nvim_get_current_line())
)

vim.api.nvim_buf_set_lines(completion_buf, 0, -1, false, { "-- " })
vim.api.nvim_win_set_cursor(0, { 1, 3 })
local requests_before_comment = #fixture_requests
local comment_menu_opened = false
vim.defer_fn(function()
	comment_menu_opened = vim.fn.pumvisible() == 1
	vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "n", false)
end, 250)
vim.api.nvim_feedkeys(vim.keycode("ive"), "xt!", false)
assert(not comment_menu_opened, "ordinary comments should not open an automatic completion menu")
assert(
	#fixture_requests == requests_before_comment,
	"typing in a comment should not send an automatic completion request"
)

vim.api.nvim_buf_set_lines(completion_buf, 0, -1, false, { "" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local requests_before_escape = #fixture_requests
vim.api.nvim_feedkeys(vim.keycode("ive<Esc>"), "xt", false)
vim.wait(150)
assert(#fixture_requests == requests_before_escape, "Escape should cancel a pending automatic completion timer")
vim.api.nvim_buf_set_lines(completion_buf, 0, -1, false, { "" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local manual_menu_opened = false
vim.defer_fn(function()
	found.manual.callback()
	vim.defer_fn(function()
		manual_menu_opened = vim.fn.pumvisible() == 1
		vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "n", false)
	end, 100)
end, 100)
vim.api.nvim_feedkeys(vim.keycode("iv"), "xt!", false)
assert(manual_menu_opened, "Ctrl-Space mapping should invoke native completion")
assert(#vim.tbl_filter(function(request)
	return request.method == "textDocument/completion"
end, fixture_requests) >= 2, "manual completion should issue a second LSP request")
vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "xt", false)
vim.lsp.get_client_by_id(fixture_id):stop(true)
vim.wait(10)
