-- Presentation around native completion: core owns candidates, resolve and docs.
local M = {}
local ready = false
local docs_epoch, signature_epoch = 0, 0
local signature_win
local pending
local styled_doc
local signature_session

local function close_signature()
	if signature_win and vim.api.nvim_win_is_valid(signature_win) then
		vim.api.nvim_win_close(signature_win, true)
	end
	signature_win = nil
end

local function cancel_signature(clear_session)
	if clear_session then
		signature_session = nil
	end
	signature_epoch = signature_epoch + 1
	if pending then
		local client, id = pending[1], pending[2]
		if client.requests and client.requests[id] then
			client:cancel_request(id)
		end
		pending = nil
	end
	close_signature()
end

local function docs_window()
	if vim.fn.pumvisible() ~= 1 then
		return
	end
	local win = vim.fn.complete_info().preview_winid
	if win and win ~= 0 and vim.api.nvim_win_is_valid(win) then
		return win
	end
end

local function style_docs(win)
	local cfg = vim.api.nvim_win_get_config(win)
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
	if cfg.relative == "" then
		return
	end
	local pos = vim.api.nvim_win_get_position(win)
	-- Preserve core's side/anchor. Never expand beyond the available grid.
	local width = math.max(1, math.min(cfg.width, 64, vim.o.columns - pos[2] - 2))
	local height = math.max(1, math.min(cfg.height, 14, vim.o.lines - pos[1] - 2))
	vim.api.nvim_win_set_config(win, {
		border = "rounded",
		title = " Documentation ",
		title_pos = "center",
		width = width,
		height = height,
	})
	vim.wo[win].winhighlight = "Normal:NormalFloat,NormalNC:NormalFloat,FloatBorder:FloatBorder,FloatTitle:FloatTitle"
	vim.wo[win].wrap = true
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
	vim.wo[win].linebreak = true
	vim.wo[win].spell = false
	vim.wo[win].signcolumn = "no"
	local buf = vim.api.nvim_win_get_buf(win)
	if vim.bo[buf].filetype == "" then
		for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
			if line:match("^%s*```") then
				vim.bo[buf].filetype = "markdown"
				break
			end
		end
	end
	-- NONE disables the global prose continuation marker for this window.
	vim.wo[win].showbreak = "NONE"
	styled_doc =
		{ win = win, buf = docbuf, tick = vim.api.nvim_buf_get_changedtick(docbuf), width = width, height = height }
end

local function watch_docs()
	docs_epoch = docs_epoch + 1
	local epoch = docs_epoch
	local function tick()
		if epoch ~= docs_epoch or vim.fn.pumvisible() ~= 1 then
			return
		end
		local win = docs_window()
		if win then
			style_docs(win)
		end
		-- Resolve may take seconds; watch only during this menu's lifetime.
		vim.defer_fn(tick, 60)
	end
	vim.schedule(tick)
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

local function trigger_signature(char)
	local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
	local was_active = signature_session and signature_session.buf == buf and signature_session.win == win or false
	cancel_signature(char == ")" or char == "]" or char == "}")
	if vim.bo[buf].buftype ~= "" or vim.b[buf].bigfile or vim.b[buf].mayon_bigfile then
		return
	end
	local client, provider
	for _, candidate in ipairs(vim.lsp.get_clients({ bufnr = buf, method = "textDocument/signatureHelp" })) do
		local spec = candidate.server_capabilities.signatureHelpProvider or {}
		if
			vim.tbl_contains(spec.triggerCharacters or {}, char)
			or (was_active and vim.tbl_contains(spec.retriggerCharacters or {}, char))
		then
			client, provider = candidate, spec
			break
		end
	end
	if not client then
		return
	end
	local epoch = signature_epoch
	vim.schedule(function()
		if epoch ~= signature_epoch or vim.api.nvim_get_current_buf() ~= buf then
			return
		end
		local tick = vim.api.nvim_buf_get_changedtick(buf)
		local cursor = vim.api.nvim_win_get_cursor(win)
		local function current()
			return epoch == signature_epoch
				and vim.api.nvim_get_current_buf() == buf
				and vim.api.nvim_get_current_win() == win
				and vim.api.nvim_get_mode().mode:sub(1, 1) == "i"
				and vim.api.nvim_buf_get_changedtick(buf) == tick
				and vim.deep_equal(vim.api.nvim_win_get_cursor(win), cursor)
				and vim.fn.pumvisible() == 0
		end
		vim.defer_fn(function()
			if not current() then
				return
			end
			local params = vim.lsp.util.make_position_params(win, client.offset_encoding)
			params.context = { triggerKind = 2, triggerCharacter = char, isRetrigger = was_active }
			local ok, id = client:request("textDocument/signatureHelp", params, function(err, result)
				if not current() or err or not result or not result.signatures or #result.signatures == 0 then
					return
				end
				pending = nil
				signature_session = { buf = buf, win = win }
				local brief = vim.deepcopy(result)
				for _, signature in ipairs(brief.signatures) do
					signature.documentation = nil
				end
				local lines, active = vim.lsp.util.convert_signature_help_to_markdown_lines(
					brief,
					vim.bo[buf].filetype,
					provider.triggerCharacters
				)
				local docbuf
				docbuf, signature_win = vim.lsp.util.open_floating_preview(lines, "markdown", {
					border = "rounded",
					title = " Signature ",
					title_pos = "center",
					focusable = false,
					max_width = math.max(1, math.min(64, vim.o.columns - 4)),
					max_height = math.max(1, math.min(4, vim.o.lines - 4)),
					close_events = { "InsertLeave", "BufLeave", "CursorMovedI" },
				})
				vim.wo[signature_win].showbreak = "NONE"
				if active then
					vim.hl.range(
						docbuf,
						vim.api.nvim_create_namespace("MayonAutoSignature"),
						"LspSignatureActiveParameter",
						{ active[1], active[2] },
						{ active[3], active[4] }
					)
				end
			end, buf)
			if ok and id then
				pending = { client, id }
			end
		end, 140)
	end)
end

function M.setup()
	if ready then
		return
	end
	ready = true
	local group = vim.api.nvim_create_augroup("MayonCompletionUI", { clear = true })
	vim.api.nvim_create_autocmd("CompleteChanged", {
		group = group,
		callback = function()
			cancel_signature()
			watch_docs()
		end,
	})
	vim.api.nvim_create_autocmd({ "CompleteDone", "InsertLeave", "BufLeave" }, {
		group = group,
		callback = function(ev)
			docs_epoch = docs_epoch + 1
			cancel_signature(ev.event ~= "CompleteDone")
		end,
	})
	vim.api.nvim_create_autocmd("TextChangedI", {
		group = group,
		callback = function()
			local cursor = vim.api.nvim_win_get_cursor(0)
			local before = vim.api.nvim_get_current_line():sub(1, cursor[2])
			trigger_signature(vim.fn.strcharpart(before, vim.fn.strchars(before) - 1, 1))
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
