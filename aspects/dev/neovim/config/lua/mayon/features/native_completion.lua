-- Native LSP completion for 0.12.6.
--
-- vim.lsp.completion's built-in autotrigger only fires on the server's
-- triggerCharacters (`.`, `:`, …). Typing an ordinary identifier never opens
-- the menu, so we drive "popup while typing identifiers" with a TextChangedI
-- debounce (~100ms) that calls vim.lsp.completion.get(). The menu, resolve and
-- docs stay owned by core; we only supply items, kind icons/detail and the
-- Tab/Enter/Escape key contract plus the repository C++ snippet source.
local M = {}
local util = require("mayon.util")

local snippets
local snippet_prefixes
local auto_timers = {}
local auto_trigger_delay = 100
local suppressed = {}
local epochs = {}
local cancel_guards = setmetatable({}, { __mode = "k" })

-- 0.12.6's core Client:cancel_request logs "Cannot find request with id X
-- whilst attempting to cancel" when the id is already gone, and still emits a
-- spurious $/cancelRequest. The completion aggregator's cancel_pending() can
-- reach such ids after a stale response is dropped. Wrap once per client and
-- keep live cancellations intact (both colon and dot call styles).
local function guard_completed_cancellation(client)
	local current = client.cancel_request
	if type(current) ~= "function" or type(client.requests) ~= "table" or cancel_guards[client] then
		return
	end
	cancel_guards[client] = true
	local original = current
	client.cancel_request = function(first, ...)
		local id = first == client and select(1, ...) or first
		if id ~= nil and client.requests[id] == nil then
			return false
		end
		if first == client then
			return original(first, ...)
		end
		return original(client, first, ...)
	end
end

-- Debounced custom autotrigger -------------------------------------------------

local function stop_auto_timer(buf)
	local timer = auto_timers[buf]
	if timer then
		auto_timers[buf] = nil
		timer:stop()
		timer:close()
	end
end

local function invalidate(buf)
	epochs[buf] = (epochs[buf] or 0) + 1
end

local function suppress(buf)
	stop_auto_timer(buf)
	invalidate(buf)
	suppressed[buf] = true
end

-- A request is only forwarded to the aggregator while its input context is
-- still current. Core already drops responses after a row/mode change, but not
-- after a same-row edit, comment transition or buffer switch, so those would
-- otherwise reopen a stale menu.
local function context_is_current(buf, win, changedtick, row, col, epoch)
	if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(win) then
		return false
	end
	if
		vim.api.nvim_get_current_buf() ~= buf
		or vim.api.nvim_get_current_win() ~= win
		or vim.api.nvim_win_get_buf(win) ~= buf
		or vim.api.nvim_buf_get_changedtick(buf) ~= changedtick
		or (epochs[buf] or 0) ~= epoch
	then
		return false
	end
	local cursor = vim.api.nvim_win_get_cursor(win)
	return cursor[1] == row and cursor[2] == col and vim.api.nvim_get_mode().mode:match("^i") ~= nil
end

-- Issue vim.lsp.completion.get() while wrapping each client's request handler so
-- a stale response (cleared input, comment, buffer switch) is dropped instead of
-- being handed to core's aggregator.
local function get_guarded(buf, changedtick)
	local win = vim.api.nvim_get_current_win()
	local cursor = vim.api.nvim_win_get_cursor(win)
	local epoch = epochs[buf] or 0
	local originals = {}
	local ok, err = pcall(function()
		for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf, method = "textDocument/completion" })) do
			local original = client.request
			originals[#originals + 1] = { client = client, request = original }
			client.request = function(self, method, params, handler, request_buf, ...)
				if method ~= "textDocument/completion" or type(handler) ~= "function" then
					return original(self, method, params, handler, request_buf, ...)
				end
				local target_buf = request_buf
				if target_buf == nil or target_buf == 0 then
					target_buf = vim.api.nvim_get_current_buf()
				end
				if target_buf ~= buf then
					return original(self, method, params, handler, request_buf, ...)
				end
				local guarded = function(err, result, context, ...)
					if not context_is_current(buf, win, changedtick, cursor[1], cursor[2], epoch) then
						return
					end
					return handler(err, result, context, ...)
				end
				return original(self, method, params, guarded, request_buf, ...)
			end
		end
		vim.lsp.completion.get()
	end)
	for _, entry in ipairs(originals) do
		entry.client.request = entry.request
	end
	if not ok then
		error(err, 0)
	end
end

local function in_comment(buf, row, col)
	if col <= 0 then
		return false
	end
	local ok, captures = pcall(vim.treesitter.get_captures_at_pos, buf, row, col - 1)
	if ok then
		for _, capture in ipairs(captures) do
			if capture.capture:lower():find("comment", 1, true) then
				return true
			end
		end
	end
	local syntax_group = vim.fn.synIDattr(vim.fn.synID(row + 1, col, 1), "name")
	return syntax_group:lower():find("comment", 1, true) ~= nil
end

local function allowed(buf)
	if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
		return false
	end
	if suppressed[buf] or vim.bo[buf].buftype ~= "" or vim.bo[buf].filetype == "bigfile" then
		return false
	end
	if vim.b[buf].completion == false or vim.g.completion == false or vim.fn.pumvisible() == 1 then
		return false
	end
	if #vim.lsp.get_clients({ bufnr = buf, method = "textDocument/completion" }) == 0 then
		return false
	end
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line = vim.api.nvim_buf_get_lines(buf, cursor[1] - 1, cursor[1], false)[1] or ""
	local word = vim.fn.matchstr(line:sub(1, cursor[2]), [[\k*$]])
	return vim.fn.strchars(word) >= 2 and not in_comment(buf, cursor[1] - 1, cursor[2])
end

local function schedule_auto(buf)
	stop_auto_timer(buf)
	if vim.api.nvim_get_current_buf() ~= buf or not allowed(buf) then
		return
	end
	local changedtick = vim.api.nvim_buf_get_changedtick(buf)
	local timer = assert(vim.uv.new_timer())
	auto_timers[buf] = timer
	timer:start(
		auto_trigger_delay,
		0,
		vim.schedule_wrap(function()
			if auto_timers[buf] ~= timer then
				return
			end
			auto_timers[buf] = nil
			timer:close()
			if
				vim.api.nvim_get_current_buf() == buf
				and vim.api.nvim_buf_is_valid(buf)
				and vim.api.nvim_buf_get_changedtick(buf) == changedtick
				and vim.api.nvim_get_mode().mode:match("^i")
				and allowed(buf)
			then
				get_guarded(buf, changedtick)
			end
		end)
	)
end

-- Repository C++ snippets ------------------------------------------------------

local function load_snippets()
	if snippets then
		return snippets
	end
	local paths = vim.api.nvim_get_runtime_file("snippets/cpp.json", true)
	local path = paths[1] or (vim.fn.stdpath("config") .. "/snippets/cpp.json")
	local file = assert(io.open(path, "r"), "missing repository C++ snippets: " .. path)
	local ok, decoded = pcall(vim.json.decode, file:read("*a"))
	file:close()
	assert(ok, "invalid C++ snippets JSON: " .. tostring(decoded))
	snippets, snippet_prefixes = {}, {}
	for _, entry in pairs(decoded) do
		local body = entry.body
		if type(body) == "table" then
			body = table.concat(body, "\n")
		end
		assert(type(entry.prefix) == "string" and type(body) == "string", "invalid C++ snippet entry")
		snippets[entry.prefix] = body
		table.insert(snippet_prefixes, entry.prefix)
	end
	table.sort(snippet_prefixes)
	return snippets
end

function M.snippet_complete(findstart, base)
	if findstart == 1 then
		local line = vim.api.nvim_get_current_line()
		local start_col = math.max(0, vim.fn.col(".") - 1)
		while start_col > 0 and line:sub(start_col, start_col):match("[%w_]") do
			start_col = start_col - 1
		end
		return start_col
	end
	local items = {}
	for _, prefix in ipairs(snippet_prefixes or vim.tbl_keys(load_snippets())) do
		if prefix:find(base, 1, true) == 1 then
			table.insert(items, {
				word = prefix,
				abbr = prefix,
				menu = "[C++ snippet]",
				info = snippets[prefix],
				user_data = vim.json.encode({ mayon_snippet = prefix }),
			})
		end
	end
	return items
end

local function expand_completed_snippet()
	local item = vim.v.completed_item
	if not item or type(item.user_data) ~= "string" or item.user_data == "" then
		return
	end
	local ok, data = pcall(vim.json.decode, item.user_data)
	local body = ok and data.mayon_snippet and load_snippets()[data.mayon_snippet]
	if not body then
		return
	end
	local cursor = vim.api.nvim_win_get_cursor(0)
	local start_col = math.max(0, cursor[2] - #item.word)
	vim.api.nvim_buf_set_text(0, cursor[1] - 1, start_col, cursor[1] - 1, cursor[2], {})
	vim.api.nvim_win_set_cursor(0, { cursor[1], start_col })
	vim.snippet.expand(body)
end

-- AI completion controller -----------------------------------------------------
-- The AI owner (copilot / deepseek ghost text) is consumed through this single
-- accessor so the menu layer never hard-wires the AI module.
local ai
local function ai_completion()
	if not ai then
		ai = require("mayon.features.ai_completion")
	end
	return ai
end

function M.tab()
	if vim.fn.pumvisible() == 1 then
		local selected = vim.fn.complete_info({ "selected" }).selected
		return selected ~= nil and selected >= 0 and "<C-y>" or "<C-n><C-y>"
	end
	if vim.snippet.active({ direction = 1 }) then
		return "<Cmd>lua vim.snippet.jump(1)<CR>"
	end
	if ai_completion().accept() then
		return ""
	end
	return "<Tab>"
end

function M.enter(menu_visible, selected)
	if menu_visible and selected ~= nil and selected >= 0 then
		return "<C-y>"
	end
	return "<CR>"
end

local function accept_word()
	if ai_completion().accept_word() then
		return ""
	end
	return vim.api.nvim_replace_termcodes("<C-Right>", true, false, true)
end

-- Item conversion (kind icons + detail truncation) ----------------------------

local kind_names = vim.lsp.protocol.CompletionItemKind
local kind_icons = require("mayon.kinds")

local function truncate_display_width(text, max_width)
	if vim.fn.strdisplaywidth(text) <= max_width then
		return text
	end
	local prefix = ""
	for count = 1, vim.fn.strchars(text) do
		local candidate = vim.fn.strcharpart(text, 0, count)
		if vim.fn.strdisplaywidth(candidate .. "…") > max_width then
			break
		end
		prefix = candidate
	end
	return prefix .. "…"
end

function M.convert(item)
	local kind = kind_names[item.kind] or "Text"
	local detail = item.detail and vim.trim(item.detail:gsub("\n.*", "")) or ""
	detail = truncate_display_width(detail, 48)
	return {
		abbr = item.label,
		kind = kind_icons[kind] or "",
		kind_hlgroup = "MayonCompletion" .. kind,
		menu = detail ~= "" and detail or kind,
	}
end

function M.attach(client, bufnr)
	if client:supports_method("textDocument/completion", bufnr) then
		guard_completed_cancellation(client)
		vim.lsp.completion.enable(true, client.id, bufnr, { autotrigger = true, convert = M.convert })
	end
end

function M.setup()
	suppressed = {}
	epochs = {}
	while next(auto_timers) do
		stop_auto_timer(next(auto_timers))
	end
	vim.o.pumborder = util.border
	vim.o.pumblend = 0
	require("mayon.features.completion_ui").setup()
	local group = vim.api.nvim_create_augroup("MayonNativeCompletion", { clear = true })

	local function configure_cpp(buf)
		vim.bo[buf].completefunc = "v:lua.require'mayon.features.native_completion'.snippet_complete"
		local complete = vim.bo[buf].complete
		if not vim.tbl_contains(vim.split(complete, ",", { plain = true }), "F") then
			vim.bo[buf].complete = complete .. (complete == "" and "" or ",") .. "F"
		end
	end
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = "cpp",
		callback = function(ev)
			configure_cpp(ev.buf)
		end,
	})
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == "cpp" then
			configure_cpp(buf)
		end
	end

	vim.api.nvim_create_autocmd("CompleteDone", { group = group, callback = expand_completed_snippet })
	vim.api.nvim_create_autocmd("TextChangedI", {
		group = group,
		callback = function(ev)
			invalidate(ev.buf)
			schedule_auto(ev.buf)
		end,
	})
	-- A menu closed with Esc stays suppressed until the next actual keystroke,
	-- so the menu's own rollback TextChangedI cannot retrigger a request.
	vim.api.nvim_create_autocmd("InsertCharPre", {
		group = group,
		callback = function(ev)
			suppressed[ev.buf] = nil
		end,
	})
	vim.api.nvim_create_autocmd("CursorMovedI", {
		group = group,
		callback = function(ev)
			invalidate(ev.buf)
		end,
	})
	vim.api.nvim_create_autocmd({ "InsertLeave", "BufLeave", "BufWipeout", "LspDetach" }, {
		group = group,
		callback = function(ev)
			stop_auto_timer(ev.buf)
			invalidate(ev.buf)
			suppressed[ev.buf] = nil
			if ev.event == "BufWipeout" then
				epochs[ev.buf] = nil
			end
		end,
	})

	vim.keymap.set("i", "<C-Space>", function()
		if vim.fn.pumvisible() == 1 then
			return
		end
		local buf = vim.api.nvim_get_current_buf()
		suppressed[buf] = nil
		stop_auto_timer(buf)
		invalidate(buf)
		if vim.lsp.completion then
			vim.lsp.completion.get()
		end
	end, { desc = "Trigger Native Completion" })
	vim.keymap.set("i", "<C-y>", function()
		return "<C-y>"
	end, { expr = true, desc = "Accept Completion" })
	vim.keymap.set("i", "<CR>", function()
		local visible = vim.fn.pumvisible() == 1
		local selected = vim.fn.complete_info({ "selected" }).selected
		if visible and selected and selected >= 0 then
			return "<C-y>"
		end
		local pairs = package.loaded["nvim-autopairs"]
		return pairs and pairs.autopairs_cr() or M.enter(visible, selected)
	end, { expr = true, desc = "Accept Completion or Insert Newline" })
	vim.keymap.set("i", "<Tab>", function()
		return M.tab()
	end, { expr = true, desc = "Accept Completion, Jump Snippet, or AI" })
	vim.keymap.set("i", "<C-Right>", accept_word, { expr = true, desc = "Accept AI Word" })
	vim.keymap.set("i", "<M-l>", accept_word, { expr = true, desc = "Accept AI Word" })
	vim.keymap.set("i", "<M-]>", function()
		ai_completion().step("next")
		return ""
	end, { expr = true, desc = "Show Next AI Completion" })
	vim.keymap.set("i", "<M-[>", function()
		ai_completion().step("prev")
		return ""
	end, { expr = true, desc = "Show Prev AI Completion" })
	vim.keymap.set("i", "<C-]>", function()
		if ai_completion().dismiss() then
			return ""
		end
		return vim.api.nvim_replace_termcodes("<C-]>", true, false, true)
	end, { expr = true, desc = "Dismiss AI Completion" })
	vim.keymap.set("i", "<Esc>", function()
		if vim.fn.pumvisible() == 1 then
			suppress(vim.api.nvim_get_current_buf())
			return "<C-e>"
		end
		if ai_completion().dismiss() then
			return ""
		end
		return vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
	end, { expr = true, nowait = true, desc = "Close Completion or Exit Insert" })
	vim.keymap.set("i", "<S-Tab>", function()
		if vim.snippet.active({ direction = -1 }) then
			return "<Cmd>lua vim.snippet.jump(-1)<CR>"
		end
		return "<C-d>"
	end, { expr = true, desc = "Jump Back or Dedent" })
end

return M
