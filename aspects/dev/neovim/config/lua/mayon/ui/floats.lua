-- Keep native LSP requests, focus/close behavior and completion resolution.
local M = {}
local ready = false

local function server()
	local clients = vim.lsp.get_clients({ bufnr = 0 })
	for _, client in ipairs(clients) do
		if client.name ~= "copilot" and client.name ~= "minuet" then
			return client.name
		end
	end
	return "LSP"
end

function M.options(kind, opts)
	return vim.tbl_extend("force", {
		border = "rounded",
		max_width = 64,
		max_height = 18,
		title = " " .. kind .. " · " .. server() .. " ",
		title_pos = "left",
	}, opts or {})
end

function M.hover()
	vim.lsp.buf.hover(M.options("hover"))
end
function M.signature()
	vim.lsp.buf.signature_help(M.options("signature"))
end

function M.setup()
	if ready then
		return
	end
	ready = true
	local original = vim.lsp.util.open_floating_preview
	vim.lsp.util.open_floating_preview = function(contents, syntax, opts)
		opts = vim.tbl_extend("keep", opts or {}, { border = "rounded", max_width = 64, max_height = 18 })
		local kind = opts.focus_id == "textDocument/hover" and "hover"
			or opts.focus_id == "textDocument/signatureHelp" and "signature"
		if not opts.title then
			kind = kind or (opts.focus_id == "vim.diagnostic.open_float" and "diagnostic") or "details"
			opts.title = " " .. kind .. " · " .. server() .. " "
			opts.title_pos = "left"
		end
		local lines = vim.deepcopy(contents)
		if kind then
			-- A Markdown rule separates the signature fence from its prose.
			local fences = 0
			for index, line in ipairs(lines) do
				if line:match("^```") then
					fences = fences + 1
				end
				if fences == 2 and index < #lines then
					if lines[index + 1] ~= "---" then
						table.insert(lines, index + 1, "---")
					end
					break
				end
			end
		end
		local buf, win = original(lines, syntax, opts)
		if win and vim.api.nvim_win_is_valid(win) then
			vim.wo[win].winhighlight =
				"Normal:NormalFloat,NormalNC:NormalFloat,FloatBorder:FloatBorder,FloatTitle:FloatTitle"
		end
		return buf, win
	end
	vim.api.nvim_create_autocmd("CompleteChanged", {
		group = vim.api.nvim_create_augroup("MayonCompletionDocs", { clear = true }),
		callback = function()
			local attempts = 0
			local function style_docs()
				attempts = attempts + 1
				local win = vim.fn.complete_info().preview_winid
				if not win or win == 0 or not vim.api.nvim_win_is_valid(win) then
					if attempts < 10 and vim.fn.pumvisible() == 1 then
						vim.defer_fn(style_docs, 20)
					end
					return
				end
				local item = vim.fn.complete_info({ "selected", "items" })
				local selected = item.items[(item.selected or -1) + 1]
				local title = selected and (selected.abbr and selected.abbr ~= "" and selected.abbr or selected.word)
					or "documentation"
				local cfg = vim.api.nvim_win_get_config(win)
				if cfg.relative ~= "" then
					vim.api.nvim_win_set_config(win, {
						border = "rounded",
						title = " " .. title .. " · completion ",
						title_pos = "left",
						width = math.min(64, math.max(cfg.width, 32, vim.fn.strdisplaywidth(title) + 16)),
					})
				end
				vim.wo[win].winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder,FloatTitle:FloatTitle"
			end
			vim.defer_fn(style_docs, 20)
		end,
	})
	local rail_buf, rail_win, selected_attr
	local function close_rail()
		if rail_win and vim.api.nvim_win_is_valid(rail_win) then
			vim.api.nvim_win_close(rail_win, true)
		end
		rail_win = nil
		selected_attr = nil
	end
	vim.api.nvim_create_autocmd("CompleteChanged", {
		group = "MayonCompletionDocs",
		callback = vim.schedule_wrap(function()
			if vim.fn.pumvisible() ~= 1 then
				return close_rail()
			end
			local pos = vim.fn.pum_getpos()
			local selected = vim.fn.complete_info({ "selected" }).selected
			if not selected or selected < 0 or not pos.row then
				return close_rail()
			end
			-- pum_getpos exposes no first-visible-item index. Compare the native
			-- selected-row screen attribute, so scrolling and an above-cursor menu
			-- keep the rail on the actual highlighted row.
			vim.cmd.redraw()
			local row
			local column = pos.col + math.max(1, pos.width - 1)
			if not selected_attr and selected < pos.height then
				row = pos.row + 1 + selected
				selected_attr = vim.fn.screenattr(row + 1, column)
			else
				for candidate = pos.row + 1, pos.row + pos.height do
					if vim.fn.screenattr(candidate + 1, column) == selected_attr then
						row = candidate
						break
					end
				end
			end
			if not row then
				return close_rail()
			end
			if not rail_buf or not vim.api.nvim_buf_is_valid(rail_buf) then
				rail_buf = vim.api.nvim_create_buf(false, true)
				vim.api.nvim_buf_set_lines(rail_buf, 0, -1, false, { "▎" })
			end
			local cfg = {
				relative = "editor",
				row = row,
				col = math.max(0, pos.col - 1),
				width = 1,
				height = 1,
				style = "minimal",
				border = "none",
				focusable = false,
				zindex = 110,
				noautocmd = true,
			}
			if rail_win and vim.api.nvim_win_is_valid(rail_win) then
				vim.api.nvim_win_set_config(rail_win, cfg)
			else
				rail_win = vim.api.nvim_open_win(rail_buf, false, cfg)
			end
			vim.wo[rail_win].winhighlight = "Normal:MayonCompletionRail,NormalFloat:MayonCompletionRail"
		end),
	})
	vim.api.nvim_create_autocmd({ "CompleteDone", "InsertLeave", "BufLeave" }, {
		group = "MayonCompletionDocs",
		callback = close_rail,
	})
end

return M
