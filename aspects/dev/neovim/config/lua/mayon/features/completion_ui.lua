-- Presentation around native completion: core owns candidates, resolve and docs.
local M = {}
local util = require("mayon.util")
local floats = require("mayon.ui.floats")
local ready = false
local styled_doc

local function docs_window()
	if vim.fn.pumvisible() ~= 1 then
		return
	end
	local win = vim.fn.complete_info().preview_winid
	if win and win ~= 0 and vim.api.nvim_win_is_valid(win) then
		return win
	end
end

-- Style core's preview after CompleteChanged or a resolve reply; skip the work
-- while its geometry and content are stable.
local function style_docs(win)
	local cfg = vim.api.nvim_win_get_config(win)
	if cfg.relative == "" then
		return
	end
	local docbuf = vim.api.nvim_win_get_buf(win)
	local tick = vim.api.nvim_buf_get_changedtick(docbuf)
	if
		styled_doc
		and styled_doc.win == win
		and styled_doc.buf == docbuf
		and styled_doc.tick == tick
		and styled_doc.width == cfg.width
		and styled_doc.height == cfg.height
	then
		return
	end
	local pos = vim.api.nvim_win_get_position(win)
	-- Preserve core's side/anchor. Never expand beyond the available grid.
	local width = math.max(1, math.min(cfg.width, 64, vim.o.columns - pos[2] - 2))
	local height = math.max(1, math.min(cfg.height, 14, vim.o.lines - pos[1] - 2))
	vim.api.nvim_win_set_config(win, {
		border = util.border,
		title = " Documentation ",
		title_pos = "center",
		width = width,
		height = height,
	})
	if vim.bo[docbuf].filetype == "" then
		for _, line in ipairs(vim.api.nvim_buf_get_lines(docbuf, 0, -1, false)) do
			if line:match("^%s*```") then
				vim.bo[docbuf].filetype = "markdown"
				break
			end
		end
	end
	util.winhl(win, {
		Normal = "NormalFloat",
		NormalNC = "NormalFloat",
		FloatBorder = "FloatBorder",
		FloatTitle = "FloatTitle",
	})
	vim.wo[win].wrap = true
	vim.wo[win].linebreak = true
	vim.wo[win].spell = false
	vim.wo[win].signcolumn = "no"
	-- NONE disables the global prose continuation marker for this window.
	vim.wo[win].showbreak = "NONE"
	local fillchars = vim.opt_local.fillchars:get()
	fillchars.lastline = " "
	vim.api.nvim_set_option_value(
		"fillchars",
		vim.iter(fillchars)
			:map(function(k, v)
				return k .. ":" .. v
			end)
			:join(","),
		{ win = win }
	)
	styled_doc = { win = win, buf = docbuf, tick = tick, width = width, height = height }
end

function M.scroll(direction)
	local win = docs_window()
	if not win then
		return false
	end
	vim.api.nvim_win_call(win, function()
		local key = direction > 0 and "\004" or "\021"
		vim.cmd.normal({ args = { key }, bang = true })
	end)
	return true
end

-- Automatic signature: a compact, unfocusable one-line hint. The explicit gK
-- mapping (lsp/init.lua) shows the full native signature help instead.
local signature = { epoch = 0 }

local function cancel_signature(clear_session)
	signature.epoch = signature.epoch + 1
	if clear_session then
		signature.session = nil
	end
	local pending = signature.pending
	signature.pending = nil
	if pending and pending.client.requests[pending.id] then
		pending.client:cancel_request(pending.id)
	end
	if signature.win and vim.api.nvim_win_is_valid(signature.win) then
		vim.api.nvim_win_close(signature.win, true)
	end
	signature.win = nil
end

local function trigger_signature(buf)
	local win = vim.api.nvim_get_current_win()
	local cursor = vim.api.nvim_win_get_cursor(win)
	local before = vim.api.nvim_get_current_line():sub(1, cursor[2])
	local char = vim.fn.strcharpart(before, vim.fn.strchars(before) - 1, 1)
	local session = signature.session
	local active = session ~= nil and session.buf == buf and session.win == win
	-- Closing brackets end the call: drop the session so "," no longer retriggers.
	cancel_signature(char == ")" or char == "]" or char == "}")
	if char == "" or vim.bo[buf].buftype ~= "" or vim.b[buf].bigfile or vim.b[buf].mayon_bigfile then
		return
	end
	if vim.fn.pumvisible() ~= 0 then
		return
	end
	local client, provider
	for _, candidate in ipairs(vim.lsp.get_clients({ bufnr = buf, method = "textDocument/signatureHelp" })) do
		local spec = candidate.server_capabilities.signatureHelpProvider or {}
		if
			vim.tbl_contains(spec.triggerCharacters or {}, char)
			or (active and vim.tbl_contains(spec.retriggerCharacters or {}, char))
		then
			client, provider = candidate, spec
			break
		end
	end
	if not client then
		return
	end
	local epoch, tick = signature.epoch, vim.api.nvim_buf_get_changedtick(buf)
	local function current()
		return epoch == signature.epoch
			and vim.api.nvim_get_current_buf() == buf
			and vim.api.nvim_get_current_win() == win
			and vim.api.nvim_get_mode().mode:sub(1, 1) == "i"
			and vim.api.nvim_buf_get_changedtick(buf) == tick
			and vim.deep_equal(vim.api.nvim_win_get_cursor(win), cursor)
			and vim.fn.pumvisible() == 0
	end
	-- One-shot debounce per trigger keystroke; any later edit invalidates it.
	vim.defer_fn(function()
		if not current() then
			return
		end
		local params = vim.lsp.util.make_position_params(win, client.offset_encoding)
		params.context = { triggerKind = 2, triggerCharacter = char, isRetrigger = active }
		local ok, id = client:request("textDocument/signatureHelp", params, function(err, result)
			if not current() or err or not result or not result.signatures or #result.signatures == 0 then
				return
			end
			signature.pending = nil
			signature.session = { buf = buf, win = win }
			local brief = vim.deepcopy(result)
			for _, item in ipairs(brief.signatures) do
				item.documentation = nil
			end
			local lines, hl = vim.lsp.util.convert_signature_help_to_markdown_lines(
				brief,
				vim.bo[buf].filetype,
				provider.triggerCharacters
			)
			if not lines or #lines == 0 then
				return
			end
			local docbuf, float = vim.lsp.util.open_floating_preview(
				lines,
				"markdown",
				floats.options("signature", {
					border = util.border,
					focusable = false,
					focus = false,
					max_width = math.max(1, math.min(64, vim.o.columns - 4)),
					max_height = math.max(1, math.min(4, vim.o.lines - 4)),
					close_events = { "CursorMovedI", "InsertLeave", "BufLeave" },
				})
			)
			signature.win = float
			vim.wo[float].showbreak = "NONE"
			if hl then
				vim.hl.range(
					docbuf,
					vim.api.nvim_create_namespace("MayonAutoSignature"),
					"LspSignatureActiveParameter",
					{ hl[1], hl[2] },
					{ hl[3], hl[4] }
				)
			end
		end, buf)
		if ok and id then
			signature.pending = { client = client, id = id }
		end
	end, 140)
end

function M.setup()
	if ready then
		return
	end
	ready = true
	local group = vim.api.nvim_create_augroup("MayonCompletionUI", { clear = true })
	local function restyle()
		local win = docs_window()
		if win then
			style_docs(win)
		end
	end
	-- Scheduled so core's own CompleteChanged handler (which resizes the preview
	-- to its text height) has already run.
	vim.api.nvim_create_autocmd("CompleteChanged", {
		group = group,
		callback = function()
			cancel_signature()
			vim.schedule(restyle)
		end,
	})
	-- completionItem/resolve fills the preview later via nvim__complete_set with
	-- no further CompleteChanged. LspRequest "complete" fires in the scheduled
	-- reply notification just before the resolve handler runs, so one more
	-- scheduled pass lands after the handler has created/resized the window.
	vim.api.nvim_create_autocmd("LspRequest", {
		group = group,
		callback = function(ev)
			local request = ev.data and ev.data.request
			if request and request.type == "complete" and request.method == "completionItem/resolve" then
				vim.schedule(restyle)
			end
		end,
	})
	vim.api.nvim_create_autocmd({ "CompleteDone", "InsertLeave", "BufLeave" }, {
		group = group,
		callback = function(ev)
			styled_doc = nil
			cancel_signature(ev.event ~= "CompleteDone")
		end,
	})
	vim.api.nvim_create_autocmd("TextChangedI", {
		group = group,
		callback = function(ev)
			trigger_signature(ev.buf)
		end,
	})
	for key, direction in pairs({ ["<C-f>"] = 1, ["<C-b>"] = -1 }) do
		vim.keymap.set("i", key, function()
			if docs_window() then
				return "<Cmd>lua require('mayon.features.completion_ui').scroll(" .. direction .. ")<CR>"
			end
			return key
		end, { expr = true, silent = true, desc = "Scroll Completion Documentation" })
	end
end

return M
