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
local fixture_requests, fixture_cancellations, fixture_closing, fixture_delay, fixture_responses = {}, {}, false, 5, 0
local fixture_completion_label = "vector"
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
					result = {
						{ label = fixture_completion_label, kind = vim.lsp.protocol.CompletionItemKind.Variable },
					}
				end
				vim.defer_fn(function()
					if method == "textDocument/completion" then
						fixture_responses = fixture_responses + 1
					end
					if on_reply then
						on_reply(id)
					end
					if not fixture_closing then
						callback(nil, result)
					end
				end, method == "initialize" and 0 or fixture_delay)
				return true, id
			end,
			notify = function(method, params)
				if method == "$/cancelRequest" then
					fixture_cancellations[#fixture_cancellations + 1] = params.id
				end
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
local fixture_client = vim.lsp.get_client_by_id(fixture_id)
local fixture_original_request = fixture_client.request
local completion_buf = vim.api.nvim_get_current_buf()
vim.bo[completion_buf].filetype = "lua"
vim.api.nvim_exec_autocmds("LspAttach", { buffer = completion_buf, data = { client_id = fixture_id } })
local cancellations_before_missing = #fixture_cancellations
assert(fixture_client:cancel_request(90001) == false, "completed request cancellation should be harmless")
assert(fixture_client.cancel_request(90002) == false, "dot-style completed request cancellation should be harmless")
assert(
	#fixture_cancellations == cancellations_before_missing,
	"missing request ids should not send cancellation notifications"
)
fixture_client.requests[90003] = { type = "pending", bufnr = completion_buf, method = "textDocument/completion" }
assert(fixture_client:cancel_request(90003), "live colon-style cancellation should be forwarded")
fixture_client.requests[90004] = { type = "pending", bufnr = completion_buf, method = "textDocument/completion" }
assert(fixture_client.cancel_request(90004), "live dot-style cancellation should be forwarded")
assert(
	vim.deep_equal(fixture_cancellations, { 90003, 90004 }),
	"the cancellation guard must preserve live request notifications and both call styles"
)
fixture_client.requests[90003], fixture_client.requests[90004] = nil, nil
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
	fixture_client.request == fixture_original_request,
	"automatic completion must restore the original client.request"
)
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

-- A slow native response must not reopen the menu after its request context
-- has been invalidated by clearing the input. Neovim 0.12.6 has no public
-- per-completion cancellation handle, so the auto-trigger adapter validates
-- the request context before forwarding the response to Neovim's aggregator.
fixture_delay = 300
vim.api.nvim_buf_set_lines(completion_buf, 0, -1, false, { "" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local completion_requests_before_stale = #vim.tbl_filter(function(request)
	return request.method == "textDocument/completion"
end, fixture_requests)
local completion_responses_before_stale = fixture_responses
local stale_result
vim.defer_fn(function()
	vim.api.nvim_feedkeys(vim.keycode("<C-u>"), "n", false)
end, 180)
vim.defer_fn(function()
	stale_result = {
		line = vim.api.nvim_get_current_line(),
		menu = vim.fn.pumvisible(),
		mode = vim.api.nvim_get_mode().mode,
	}
	vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "n", false)
end, 600)
vim.api.nvim_feedkeys(vim.keycode("ive"), "xt!", false)
assert(stale_result and stale_result.line == "", "slow completion fixture should clear its input")
assert(stale_result.menu == 0, "late LSP response reopened completion after Ctrl-U")
local completion_requests_after_stale = #vim.tbl_filter(function(request)
	return request.method == "textDocument/completion"
end, fixture_requests)
assert(
	completion_requests_after_stale == completion_requests_before_stale + 1,
	"clearing the line should issue exactly one request and suppress its late result"
)
assert(
	fixture_responses == completion_responses_before_stale + 1,
	"slow LSP fixture must deliver its response before stale-menu suppression is checked"
)

vim.api.nvim_buf_set_lines(completion_buf, 0, -1, false, { "" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local moved_result
vim.defer_fn(function()
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
end, 180)
vim.defer_fn(function()
	moved_result = {
		menu = vim.fn.pumvisible(),
		mode = vim.api.nvim_get_mode().mode,
	}
	vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "n", false)
end, 600)
vim.api.nvim_feedkeys(vim.keycode("ive"), "xt!", false)
assert(moved_result and moved_result.menu == 0, "late LSP response should not open a menu at a moved cursor")

vim.api.nvim_buf_set_lines(completion_buf, 0, -1, false, { "" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local comment_result
local responses_before_comment_stale = fixture_responses
vim.defer_fn(function()
	vim.api.nvim_buf_set_lines(completion_buf, 0, -1, false, { "--" })
	vim.api.nvim_win_set_cursor(0, { 1, 2 })
end, 180)
vim.defer_fn(function()
	comment_result = {
		line = vim.api.nvim_get_current_line(),
		menu = vim.fn.pumvisible(),
	}
	vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "n", false)
end, 600)
vim.api.nvim_feedkeys(vim.keycode("ive"), "xt!", false)
assert(comment_result and comment_result.line == "--", "comment transition should remain in place")
assert(comment_result.menu == 0, "late LSP response should not open a menu after entering a comment")
assert(
	fixture_responses == responses_before_comment_stale + 1,
	"comment transition regression must observe the delayed response"
)

vim.api.nvim_buf_set_lines(completion_buf, 0, -1, false, { "" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local switched_result
local responses_before_switch = fixture_responses
local other_buf = vim.api.nvim_create_buf(false, true)
vim.defer_fn(function()
	vim.api.nvim_set_current_buf(other_buf)
end, 180)
vim.defer_fn(function()
	switched_result = {
		buf = vim.api.nvim_get_current_buf(),
		menu = vim.fn.pumvisible(),
		mode = vim.api.nvim_get_mode().mode,
	}
	vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "n", false)
end, 600)
vim.api.nvim_feedkeys(vim.keycode("ive"), "xt!", false)
assert(switched_result and switched_result.buf == other_buf, "buffer-switch fixture should leave the request buffer")
assert(switched_result.menu == 0, "late LSP response should not open a menu in another buffer")
assert(
	switched_result.mode:match("^i"),
	"buffer-switch fixture should remain in insert mode for the stale-response check"
)
assert(fixture_responses == responses_before_switch + 1, "buffer-switch regression must observe the delayed response")
vim.api.nvim_set_current_buf(completion_buf)
fixture_delay = 5

-- A manual refresh at the same cursor must supersede an older automatic
-- request even when the server ignores the cancellation signal.
vim.api.nvim_buf_set_lines(completion_buf, 0, -1, false, { "" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
fixture_delay = 300
fixture_completion_label = "vector_auto_late"
local responses_before_manual_refresh = fixture_responses
local manual_refresh_result
vim.defer_fn(function()
	fixture_delay = 5
	fixture_completion_label = "vector_manual"
	found.manual.callback()
end, 180)
vim.defer_fn(function()
	manual_refresh_result = {
		menu = vim.fn.pumvisible(),
		responses = fixture_responses,
		items = vim.fn.complete_info({ "items" }).items,
	}
	vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "n", false)
end, 600)
vim.api.nvim_feedkeys(vim.keycode("ive"), "xt!", false)
assert(
	manual_refresh_result and manual_refresh_result.menu == 1,
	"late automatic response must not replace the manual completion menu"
)
assert(
	manual_refresh_result.responses == responses_before_manual_refresh + 2,
	"manual refresh test must observe both the manual and delayed automatic responses"
)
assert(
	vim.tbl_contains(
		vim.tbl_map(function(item)
			return item.word
		end, manual_refresh_result.items),
		"vector_manual"
	),
	"late automatic response must not replace the manual candidate"
)
assert(
	not vim.tbl_contains(
		vim.tbl_map(function(item)
			return item.word
		end, manual_refresh_result.items),
		"vector_auto_late"
	),
	"stale automatic candidate must not be mixed into the manual result"
)
fixture_delay = 5
fixture_completion_label = "vector"

vim.api.nvim_buf_set_lines(completion_buf, 0, -1, false, { "" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local requests_before_escape = #fixture_requests
vim.api.nvim_feedkeys(vim.keycode("ive<Esc>"), "xt", false)
vim.wait(150)
assert(#fixture_requests == requests_before_escape, "Escape should cancel a pending automatic completion timer")
vim.api.nvim_buf_set_lines(completion_buf, 0, -1, false, { "" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
local manual_menu_opened = false
local manual_requests_before = #vim.tbl_filter(function(request)
	return request.method == "textDocument/completion"
end, fixture_requests)
vim.defer_fn(function()
	found.manual.callback()
	vim.defer_fn(function()
		manual_menu_opened = vim.fn.pumvisible() == 1
		vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "n", false)
	end, 150)
end, 20)
vim.api.nvim_feedkeys(vim.keycode("iv"), "xt!", false)
assert(
	manual_menu_opened,
	"Ctrl-Space mapping should invoke native completion; requests="
		.. vim.inspect(fixture_requests)
		.. ", line="
		.. vim.api.nvim_get_current_line()
)
assert(
	#vim.tbl_filter(function(request)
			return request.method == "textDocument/completion"
		end, fixture_requests) == manual_requests_before + 1,
	"manual refresh should replace the pending timer, not duplicate it"
)
vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "xt", false)
vim.lsp.get_client_by_id(fixture_id):stop(true)
vim.wait(10)
