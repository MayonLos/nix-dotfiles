local ui = require("mayon.features.completion_ui")
ui.setup()
ui.setup()
assert(#vim.api.nvim_get_autocmds({ group = "MayonCompletionUI", event = "CompleteChanged" }) == 1)
assert(#vim.api.nvim_get_autocmds({ group = "MayonCompletionUI", event = "LspRequest" }) == 1)
assert(#vim.api.nvim_get_autocmds({ group = "MayonCompletionUI", event = "TextChangedI" }) == 1)

-- Documentation: events style core's preview without a polling loop.
local original_info, original_pum = vim.fn.complete_info, vim.fn.pumvisible
local visible, preview = true, nil
vim.fn.pumvisible = function()
	return visible and 1 or 0
end
vim.fn.complete_info = function(fields)
	assert(fields == nil, "Neovim 0.12 preview_winid is available only in the unfiltered result")
	return { preview_winid = preview }
end
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
local old_eventignore = vim.o.eventignore
vim.o.eventignore = "FileType"
vim.api.nvim_exec_autocmds("CompleteChanged", {})
-- Styling is scheduled behind core's own CompleteChanged resize.
vim.wait(20)
vim.o.eventignore = old_eventignore
assert(vim.bo[buf].filetype == "markdown", "completion documents should render as Markdown")
assert(vim.api.nvim_win_get_height(preview) <= 14)
assert(vim.wo[preview].showbreak == "NONE", "completion docs must override Markdown continuation arrows")
assert(
	vim.wo[preview].spell == false and vim.wo[preview].wrap and vim.wo[preview].linebreak,
	vim.inspect({ spell = vim.wo[preview].spell, wrap = vim.wo[preview].wrap, linebreak = vim.wo[preview].linebreak })
)
local config = vim.api.nvim_win_get_config(preview)
assert(config.border[1] == "╭", "completion docs should use the shared rounded border")
assert(config.title[1][1] == " Documentation ")
local view_before = vim.api.nvim_win_call(preview, vim.fn.winsaveview)
assert(ui.scroll(1))
assert(vim.api.nvim_win_call(preview, vim.fn.winsaveview).topline > view_before.topline)
assert(ui.scroll(-1))
assert(vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), lines), "styling must preserve LSP text")
visible = false
assert(ui.scroll(1) == false, "no documentation must preserve native Ctrl-f fallback")
vim.api.nvim_exec_autocmds("CompleteDone", {})
assert(vim.api.nvim_win_is_valid(preview), "our cleanup must not close core's preview window")
vim.api.nvim_win_close(preview, true)
vim.api.nvim_buf_delete(buf, { force = true })
vim.fn.complete_info, vim.fn.pumvisible = original_info, original_pum

-- A tiny in-process server: completion resolve and signature help. Replies are
-- delivered like vim.lsp.rpc does: reply notification first, handler second.
local next_id = 0
local completion_items = { { label = "abc" }, { label = "abd" } }
local signature_doc = "Long prose that the automatic hint must not show."
local function server()
	local closing = false
	return {
		request = function(method, params, callback, notify_reply)
			next_id = next_id + 1
			local id = next_id
			local result
			if method == "initialize" then
				result = {
					capabilities = {
						completionProvider = { resolveProvider = true },
						signatureHelpProvider = { triggerCharacters = { "(" }, retriggerCharacters = { "," } },
					},
				}
			elseif method == "textDocument/completion" then
				result = { isIncomplete = false, items = completion_items }
			elseif method == "completionItem/resolve" then
				local doc = {}
				for n = 1, 40 do
					doc[#doc + 1] = ("resolved line %d %s"):format(n, string.rep("x", 90))
				end
				result = { label = "abc", documentation = { kind = "plaintext", value = table.concat(doc, "\n") } }
			elseif method == "textDocument/signatureHelp" then
				-- Like real servers: no signature once the call is closed.
				local line = vim.api.nvim_buf_get_lines(0, params.position.line, params.position.line + 1, false)[1]
				local before = line:sub(1, params.position.character)
				local _, opened = before:gsub("%(", "")
				local _, closed = before:gsub("%)", "")
				result = opened > closed
						and {
							signatures = {
								{
									label = "f(int a, int b)",
									documentation = signature_doc,
									parameters = { { label = "int a" }, { label = "int b" } },
								},
							},
							activeParameter = 0,
						}
					or nil
			end
			vim.schedule(function()
				if notify_reply then
					notify_reply(id)
				end
			end)
			vim.schedule(function()
				callback(nil, result)
			end)
			return true, id
		end,
		notify = function()
			return true
		end,
		is_closing = function()
			return closing
		end,
		terminate = function()
			closing = true
		end,
	}
end

local function floating_windows()
	return vim.tbl_filter(function(win)
		return vim.api.nvim_win_get_config(win).relative ~= ""
	end, vim.api.nvim_list_wins())
end

vim.cmd.enew()
-- A filetype without configured servers keeps real ones (clangd) out.
vim.bo.filetype = "mayonfixture"
local client_id = assert(vim.lsp.start({ name = "ui-fixture", cmd = server, root_dir = vim.fn.getcwd() }))
assert(vim.wait(1000, function()
	return #vim.lsp.get_clients({ bufnr = 0, name = "ui-fixture" }) > 0
end))
local main = vim.api.nvim_get_current_win()

-- Resolved documentation arrives after CompleteChanged; it must still be styled.
vim.o.completeopt = "menuone,noselect,popup"
-- Insert-mode scenarios: feedkeys "x!" keeps Insert mode while timers feed
-- each step and check the result; the last step leaves Insert mode.
local function drive(steps)
	local failure
	local function run(index)
		local step = steps[index]
		if not step or failure then
			-- <C-e> dismisses a still-open menu so <Esc> leaves Insert mode.
			vim.api.nvim_feedkeys(vim.keycode("<C-e><Esc>"), "n", false)
			return
		end
		vim.api.nvim_feedkeys(vim.keycode(step[1]), "t", false)
		vim.defer_fn(function()
			local ok, err = pcall(step[2])
			failure = not ok and err or nil
			run(index + 1)
		end, step[3] or 300)
	end
	vim.defer_fn(function()
		run(1)
	end, 0)
	vim.api.nvim_feedkeys("a", "tx!", false)
	assert(not failure, failure)
end

drive({
	{
		"<Cmd>lua vim.lsp.completion.get()<CR>",
		function() end,
		200,
	},
	{
		"<C-n>",
		function()
			local win = vim.fn.complete_info().preview_winid
			assert(win and win ~= 0 and vim.api.nvim_win_is_valid(win), "resolve should fill the preview")
			local cfg = vim.api.nvim_win_get_config(win)
			assert(type(cfg.border) == "table" and cfg.border[1] == "╭", "resolved docs need the rounded border")
			assert(type(cfg.title) == "table" and cfg.title[1][1] == " Documentation ", vim.inspect(cfg.title))
			assert(vim.api.nvim_win_get_height(win) <= 14, "resolved docs height must stay capped")
		end,
		600,
	},
	{ "<C-e>", function() end, 50 },
})

-- Automatic signature: compact, unfocusable, closes once typing moves on.
local function signature_float()
	local wins = floating_windows()
	return #wins == 1 and wins[1] or nil
end
local function in_insert(tag)
	assert(
		vim.api.nvim_get_current_win() == main and vim.api.nvim_get_mode().mode == "i",
		("%s main=%s mode=%s"):format(
			tag,
			tostring(vim.api.nvim_get_current_win() == main),
			vim.api.nvim_get_mode().mode
		)
	)
end
-- Keep autotriggered completion out of the way of the signature hint.
completion_items = {}
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
drive({
	{
		"f(",
		function()
			local float = assert(
				signature_float(),
				"typing ( should open the signature hint "
					.. vim.v.errmsg
					.. vim.inspect(vim.tbl_map(function(n)
						return n.msg
					end, Snacks.notifier.get_history()))
					.. vim.inspect({
						vim.tbl_map(function(w)
							return vim.bo[vim.api.nvim_win_get_buf(w)].filetype
								.. "|"
								.. vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(w))
						end, floating_windows()),
						vim.fn.pumvisible(),
						_G.DBG,
						vim.api.nvim_get_current_line(),
						vim.bo.buftype,
						vim.b.bigfile,
					})
			)
			local cfg = vim.api.nvim_win_get_config(float)
			assert(cfg.border[1] == "╭", "signature hint uses the rounded border")
			assert(cfg.focusable == false, "automatic signature must not be focusable")
			assert(vim.api.nvim_win_get_height(float) <= 4, "automatic signature must stay compact")
			local text = table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(float), 0, -1, false), "\n")
			assert(not text:find(signature_doc, 1, true), "automatic signature strips documentation prose")
		end,
	},
	{
		"x,",
		function()
			in_insert("retrigger must not steal focus")
			assert(signature_float(), "the retrigger character should reopen the hint")
		end,
	},
	{
		"y);",
		function()
			in_insert("closing the call keeps typing in place")
			assert(#floating_windows() == 0, "closing the call must close the hint")
		end,
	},
	{
		",",
		function()
			assert(#floating_windows() == 0, "a comma outside an active call must not retrigger")
		end,
	},
	{
		"<CR>g(",
		function()
			assert(signature_float(), "a new call opens the hint again")
		end,
	},
	{
		"1",
		function()
			in_insert("typing an argument")
			assert(#floating_windows() == 0, "further typing closes the hint")
		end,
	},
})
assert(vim.api.nvim_get_mode().mode == "n")
vim.lsp.get_client_by_id(client_id):stop(true)
print("native completion UI checks passed")
