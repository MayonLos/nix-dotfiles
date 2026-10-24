local M = {}

local snippets
local snippet_prefixes

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

	vim.keymap.set("i", "<C-Space>", function()
		if vim.lsp.completion then
			vim.lsp.completion.get()
		end
	end, { desc = "Trigger native LSP completion" })
	vim.keymap.set("i", "<C-y>", function()
		return "<C-y>"
	end, { expr = true, desc = "Accept selected completion" })
	vim.keymap.set("i", "<CR>", function()
		local visible = vim.fn.pumvisible() == 1
		local selected = vim.fn.complete_info({ "selected" }).selected
		if visible and selected and selected >= 0 then
			return "<C-y>"
		end
		local pairs = package.loaded["nvim-autopairs"]
		return pairs and pairs.autopairs_cr() or M.enter(visible, selected)
	end, { expr = true, desc = "Accept selected completion or insert newline" })
	vim.keymap.set("i", "<Tab>", function()
		return M.tab()
	end, { expr = true, desc = "Accept AI completion, jump snippet, or indent" })
	local function accept_word()
		if require("mayon.features.ai_completion").accept_word() then
			return ""
		end
		return vim.api.nvim_replace_termcodes("<C-Right>", true, false, true)
	end
	vim.keymap.set("i", "<C-Right>", accept_word, { expr = true, desc = "Accept one AI completion word" })
	vim.keymap.set("i", "<M-l>", accept_word, { expr = true, desc = "Accept one AI completion word" })
	vim.keymap.set("i", "<M-]>", function()
		require("mayon.features.ai_completion").step("next")
		return ""
	end, { expr = true, desc = "Next AI completion candidate" })
	vim.keymap.set("i", "<M-[>", function()
		require("mayon.features.ai_completion").step("prev")
		return ""
	end, { expr = true, desc = "Previous AI completion candidate" })
	vim.keymap.set("i", "<C-]>", function()
		if require("mayon.features.ai_completion").dismiss() then
			return ""
		end
		return vim.api.nvim_replace_termcodes("<C-]>", true, false, true)
	end, { expr = true, desc = "Dismiss AI completion" })
	vim.keymap.set("i", "<Esc>", function()
		if require("mayon.features.ai_completion").dismiss() then
			return ""
		end
		return vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
	end, { expr = true, desc = "Dismiss AI completion or leave insert mode" })
	vim.keymap.set("i", "<S-Tab>", function()
		if vim.snippet.active({ direction = -1 }) then
			return "<Cmd>lua vim.snippet.jump(-1)<CR>"
		end
		return "<C-d>"
	end, { expr = true, desc = "Jump backward in snippet or dedent" })
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
		kind = (kind_icons[kind] or "") .. " " .. kind,
		menu = detail,
	}
end

function M.attach(client, bufnr)
	if client:supports_method("textDocument/completion", bufnr) then
		vim.lsp.completion.enable(true, client.id, bufnr, { autotrigger = true, convert = M.convert })
	end
end

return M
