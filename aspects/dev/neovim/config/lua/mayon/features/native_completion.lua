local M = {}

local snippets
local snippet_prefixes
local auto_timers = {}
local auto_trigger_delay = 100

local function stop_auto_timer(buf)
	local timer = auto_timers[buf]
	if timer then
		auto_timers[buf] = nil
		timer:stop()
		timer:close()
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

local function auto_completion_allowed(buf)
	if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
		return false
	end
	if vim.bo[buf].buftype ~= "" or vim.bo[buf].filetype == "bigfile" then
		return false
	end
	if vim.b[buf].completion == false or vim.g.completion == false or vim.fn.pumvisible() == 1 then
		return false
	end
	local clients = vim.lsp.get_clients({ bufnr = buf, method = "textDocument/completion" })
	if #clients == 0 then
		return false
	end
	local cursor = vim.api.nvim_win_get_cursor(0)
	local line = vim.api.nvim_buf_get_lines(buf, cursor[1] - 1, cursor[1], false)[1] or ""
	local prefix = line:sub(1, cursor[2])
	local word = vim.fn.matchstr(prefix, [[\k*$]])
	if vim.fn.strchars(word) < 2 or in_comment(buf, cursor[1] - 1, cursor[2]) then
		return false
	end
	return true
end

local function schedule_auto_completion(buf)
	stop_auto_timer(buf)
	if vim.api.nvim_get_current_buf() ~= buf or not auto_completion_allowed(buf) then
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
				and auto_completion_allowed(buf)
			then
				vim.lsp.completion.get()
			end
		end)
	)
end

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
	local buf = vim.api.nvim_get_current_buf()
	local cursor = vim.api.nvim_win_get_cursor(0)
	local start_col = math.max(0, cursor[2] - #item.word)
	vim.api.nvim_buf_set_text(buf, cursor[1] - 1, start_col, cursor[1] - 1, cursor[2], {})
	vim.api.nvim_win_set_cursor(0, { cursor[1], start_col })
	vim.snippet.expand(body)
end

function M.setup()
	while next(auto_timers) do
		local buf = next(auto_timers)
		stop_auto_timer(buf)
	end
	-- The completion menu is a compact, borderless surface. Its columns inherit
	-- PmenuKind (blue) and PmenuExtra (muted) from the One Dark palette.
	vim.o.pumborder = "none"
	vim.o.pumblend = 0
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
			schedule_auto_completion(ev.buf)
		end,
	})
	vim.api.nvim_create_autocmd({ "InsertLeave", "BufLeave", "BufWipeout", "LspDetach" }, {
		group = group,
		callback = function(ev)
			stop_auto_timer(ev.buf)
		end,
	})

	vim.keymap.set("i", "<C-Space>", function()
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
	end, { expr = true, desc = "Accept Completion or Newline" })
	vim.keymap.set("i", "<Tab>", function()
		return M.tab()
	end, { expr = true, desc = "Accept AI, Expand, or Indent" })
	local function accept_word()
		if require("mayon.features.ai_completion").accept_word() then
			return ""
		end
		return vim.api.nvim_replace_termcodes("<C-Right>", true, false, true)
	end
	vim.keymap.set("i", "<C-Right>", accept_word, { expr = true, desc = "Accept AI Word" })
	vim.keymap.set("i", "<M-l>", accept_word, { expr = true, desc = "Accept AI Word" })
	vim.keymap.set("i", "<M-]>", function()
		require("mayon.features.ai_completion").step("next")
		return ""
	end, { expr = true, desc = "Show Next AI Completion" })
	vim.keymap.set("i", "<M-[>", function()
		require("mayon.features.ai_completion").step("prev")
		return ""
	end, { expr = true, desc = "Show Prev AI Completion" })
	vim.keymap.set("i", "<C-]>", function()
		if require("mayon.features.ai_completion").dismiss() then
			return ""
		end
		return vim.api.nvim_replace_termcodes("<C-]>", true, false, true)
	end, { expr = true, desc = "Dismiss AI Completion" })
	vim.keymap.set("i", "<Esc>", function()
		if require("mayon.features.ai_completion").dismiss() then
			return ""
		end
		return vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
	end, { expr = true, desc = "Dismiss Completion or Exit" })
	vim.keymap.set("i", "<S-Tab>", function()
		if vim.snippet.active({ direction = -1 }) then
			return "<Cmd>lua vim.snippet.jump(-1)<CR>"
		end
		return "<C-d>"
	end, { expr = true, desc = "Jump Back or Dedent" })
end

function M.tab()
	local ai = require("mayon.features.ai_completion")
	if vim.fn.pumvisible() == 0 and ai.accept() then
		return ""
	end
	if vim.snippet.active({ direction = 1 }) then
		return "<Cmd>lua vim.snippet.jump(1)<CR>"
	end
	return "<Tab>"
end

function M.enter(menu_visible, selected)
	if menu_visible and selected ~= nil and selected >= 0 then
		return "<C-y>"
	end
	return "<CR>"
end

local kind_names = vim.lsp.protocol.CompletionItemKind
local kind_icons = require("mayon.kinds")
function M.convert(item)
	local kind = kind_names[item.kind] or "Text"
	local detail = item.detail and vim.trim(item.detail:gsub("\n.*", "")) or ""
	if #detail > 48 then
		detail = detail:sub(1, 45) .. "…"
	end
	return {
		abbr = item.label:gsub("%b()", ""),
		kind = kind_icons[kind] or "",
		menu = detail ~= "" and detail or kind,
	}
end

function M.attach(client, bufnr)
	if client:supports_method("textDocument/completion", bufnr) then
		vim.lsp.completion.enable(true, client.id, bufnr, { autotrigger = true, convert = M.convert })
	end
end

return M
