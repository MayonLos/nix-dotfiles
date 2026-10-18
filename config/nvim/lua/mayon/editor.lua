-- Small editor conveniences implemented with Neovim's own APIs.
-- Loaded explicitly by the Nix module; this file has no plugin dependencies.
local M = {}

local ns = {
	indent = vim.api.nvim_create_namespace("mayon.editor.indent"),
	words = vim.api.nvim_create_namespace("mayon.editor.words"),
	dim = vim.api.nvim_create_namespace("mayon.editor.dim"),
}

local config = {
	indent_char = "│",
	scope_scan_lines = 2000,
	scroll_duration = 120,
	bigfile_size = 1024 * 1024,
}
local scroll_timers, zen_state, dim_enabled = {}, nil, false
local status_cache = { signs = {}, marks = {} }
local status_timer
local setup_done = false
local render_states, refresh_pending = {}, {}
local update_window

local function valid_buf(buf)
	return vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].buftype == ""
end

local function visible_range(win)
	if not vim.api.nvim_win_is_valid(win) then
		return nil
	end
	local buf = vim.api.nvim_win_get_buf(win)
	if not valid_buf(buf) then
		return nil
	end
	local info = vim.fn.getwininfo(win)[1]
	if not info then
		return nil
	end
	local first = math.max(0, info.topline - 1)
	local last = math.min(vim.api.nvim_buf_line_count(buf) - 1, info.botline - 1)
	return buf, first, last, info
end

local function indent_columns(line, tabstop)
	local col = 0
	for i = 1, #(line:match("^%s*") or "") do
		if line:byte(i) == 9 then
			col = col + tabstop - (col % tabstop)
		else
			col = col + 1
		end
	end
	return col
end

local function schedule_refresh(buf)
	if not valid_buf(buf) or vim.b[buf].mayon_bigfile then
		return
	end
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		if not refresh_pending[win] then
			refresh_pending[win] = true
			vim.schedule(function()
				refresh_pending[win] = nil
				if update_window and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
					update_window(win)
				end
			end)
		end
	end
end

local function scope_from_indent(buf, row)
	local count = vim.api.nvim_buf_line_count(buf)
	local function indent_at(line)
		if line < 0 or line >= count then
			return -1
		end
		local text = vim.api.nvim_buf_get_lines(buf, line, line + 1, false)[1] or ""
		if text:match("^%s*$") then
			return nil
		end
		return indent_columns(text, math.max(1, vim.bo[buf].tabstop))
	end
	local base = indent_at(row)
	if base == nil then
		local prev_line, next_line, prev_indent, next_indent
		for line = row - 1, math.max(0, row - config.scope_scan_lines), -1 do
			prev_indent = indent_at(line)
			if prev_indent ~= nil then
				prev_line = line
				break
			end
		end
		for line = row + 1, math.min(count - 1, row + config.scope_scan_lines) do
			next_indent = indent_at(line)
			if next_indent ~= nil then
				next_line = line
				break
			end
		end
		if prev_line and next_line then
			row = math.abs(row - prev_line) <= math.abs(next_line - row) and prev_line or next_line
		else
			row = prev_line or next_line or row
		end
		base = indent_at(row)
	end
	base = base or 0
	local first, last = row, row
	for line = row - 1, math.max(0, row - config.scope_scan_lines), -1 do
		local level = indent_at(line)
		if level ~= nil and level < base then
			break
		end
		first = line
	end
	for line = row + 1, math.min(count - 1, row + config.scope_scan_lines) do
		local level = indent_at(line)
		if level ~= nil and level < base then
			break
		end
		last = line
	end
	local before = first > 0 and indent_at(first - 1) or nil
	local after = last + 1 < count and indent_at(last + 1) or nil
	local edge = math.min(math.max(before or base, after or base), base)
	if before == edge then
		first = first - 1
	end
	if after == edge then
		last = last + 1
	end
	return first, last, base
end

local scope_types = {
	block = true,
	compound_statement = true,
	function_definition = true,
	function_declaration = true,
	function_declarator = true,
	class_definition = true,
	class_declaration = true,
	method_declaration = true,
	if_statement = true,
	for_statement = true,
	while_statement = true,
	switch_statement = true,
	do_statement = true,
	try_statement = true,
	table_constructor = true,
	lexical_declaration = true,
	arrow_function = true,
	["function"] = true,
}

local function current_scope(buf, row, col)
	if vim.treesitter and vim.treesitter.get_node and not vim.b[buf].mayon_bigfile then
		local ok, node = pcall(vim.treesitter.get_node, { bufnr = buf, pos = { row, col } })
		if ok then
			local chosen
			while node do
				local ok_range, sr, sc, er, ec = pcall(node.range, node)
				if ok_range and er > sr and scope_types[node:type()] then
					chosen = { sr, ec > 0 and er or er - 1, sc }
					break
				end
				node = node:parent()
			end
			if chosen then
				local text = vim.api.nvim_buf_get_lines(buf, chosen[1], chosen[1] + 1, false)[1] or ""
				local leading = indent_columns(text, math.max(1, vim.bo[buf].tabstop))
				return chosen[1], chosen[2], leading + math.max(1, vim.bo[buf].shiftwidth)
			end
		end
	end
	return scope_from_indent(buf, row)
end

local function current_word(line, col)
	local function is_word(pos)
		return pos >= 1 and pos <= #line and line:sub(pos, pos):match("[%w_]") ~= nil
	end
	local pos = col + 1
	if not is_word(pos) then
		if not is_word(pos - 1) then
			return nil
		end
		pos = pos - 1
	end
	local first, last = pos, pos
	while is_word(first - 1) do
		first = first - 1
	end
	while is_word(last + 1) do
		last = last + 1
	end
	return line:sub(first, last)
end

local function render_window(win)
	local buf, first, last = visible_range(win)
	if not buf then
		render_states[win] = nil
		return
	end
	if vim.b[buf].mayon_bigfile then
		render_states[win] = nil
		return
	end

	local cursor = vim.api.nvim_win_get_cursor(win)
	local scope_first, scope_last, scope_col = current_scope(buf, cursor[1] - 1, cursor[2])
	local cursor_line = vim.api.nvim_buf_get_lines(buf, cursor[1] - 1, cursor[1], false)[1] or ""
	local word = current_word(cursor_line, cursor[2])
	local shiftwidth = vim.bo[buf].shiftwidth
	if shiftwidth == 0 then
		shiftwidth = vim.bo[buf].tabstop
	end
	shiftwidth = math.max(1, shiftwidth)
	local decorations = { [ns.indent] = {}, [ns.words] = {}, [ns.dim] = {} }
	local matches = 0

	local lines = vim.api.nvim_buf_get_lines(buf, first, last + 1, false)
	local indents = {}
	for index, line in ipairs(lines) do
		if line:match("^%s*$") then
			local before, after
			for i = index - 1, 1, -1 do
				if not lines[i]:match("^%s*$") then
					before = indents[i]
					break
				end
			end
			for i = index + 1, #lines do
				if not lines[i]:match("^%s*$") then
					after = indent_columns(lines[i], math.max(1, vim.bo[buf].tabstop))
					break
				end
			end
			if before and after then
				indents[index] = math.min(before, after)
				if before ~= after and indents[index] > 0 then
					indents[index] = indents[index] + shiftwidth
				end
			else
				indents[index] = before or after or 0
			end
		else
			indents[index] = indent_columns(line, math.max(1, vim.bo[buf].tabstop))
		end
	end

	for row = first, last do
		local line = lines[row - first + 1] or ""
		local indent = indents[row - first + 1] or 0
		local depth = math.floor(indent / shiftwidth)
		for level = 0, depth - 1 do
			local is_scope = row >= scope_first and row <= scope_last and (level + 1) * shiftwidth == scope_col
			decorations[ns.indent][row] = decorations[ns.indent][row] or {}
			table.insert(decorations[ns.indent][row], {
				col = 0,
				opts = {
					virt_text = { { config.indent_char, is_scope and "MayonIndentScope" or "MayonIndent" } },
					virt_text_win_col = level * shiftwidth,
					hl_mode = "combine",
					priority = is_scope and 8 or 7,
				},
			})
		end

		if dim_enabled and (row < scope_first or row > scope_last) then
			decorations[ns.dim][row] = { { col = 0, opts = { line_hl_group = "MayonDim", priority = 1 } } }
		end

		if word and #word >= 2 and matches < 300 then
			local from = 1
			while matches < 300 do
				local start_at, end_at = line:find(word, from, true)
				if not start_at then
					break
				end
				local before, after = line:sub(start_at - 1, start_at - 1), line:sub(end_at + 1, end_at + 1)
				if not before:match("[%w_]") and not after:match("[%w_]") then
					decorations[ns.words][row] = decorations[ns.words][row] or {}
					table.insert(decorations[ns.words][row], {
						col = start_at - 1,
						opts = { end_col = end_at, hl_group = "MayonWord", priority = 110 },
					})
					matches = matches + 1
				end
				from = end_at + 1
			end
		end
	end

	render_states[win] = {
		buf = buf,
		changedtick = vim.api.nvim_buf_get_changedtick(buf),
		cursor = cursor,
		top = first,
		bottom = last,
		decorations = decorations,
	}
	vim.cmd.redraw()
end

update_window = render_window

for namespace in pairs(ns) do
	local provider_ns = ns[namespace]
	vim.api.nvim_set_decoration_provider(provider_ns, {
		on_win = function(_, win, buf)
			local state = render_states[win]
			if not state or state.buf ~= buf or not vim.api.nvim_buf_is_valid(buf) then
				return false
			end
			if state.changedtick ~= vim.api.nvim_buf_get_changedtick(buf) then
				return false
			end
			local cursor = vim.api.nvim_win_get_cursor(win)
			return state.cursor[1] == cursor[1] and state.cursor[2] == cursor[2]
		end,
		on_line = function(_, win, buf, row)
			local state = render_states[win]
			if not state or state.buf ~= buf then
				return
			end
			local marks = state.decorations[provider_ns][row] or {}
			for _, mark in ipairs(marks) do
				local opts = vim.tbl_extend("force", mark.opts, { ephemeral = true })
				pcall(vim.api.nvim_buf_set_extmark, buf, provider_ns, row, mark.col, opts)
			end
		end,
	})
end

M._render_window = render_window
M._render_state = function(win)
	return render_states[win]
end

function M.scope_jump(opts)
	opts = opts or {}
	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_get_current_buf()
	local row = vim.api.nvim_win_get_cursor(win)[1] - 1
	local first, last = current_scope(buf, row, vim.api.nvim_win_get_cursor(win)[2])
	local target = opts.bottom and last or first
	if target == row then
		vim.notify("Already at the scope boundary", vim.log.levels.INFO)
		return
	end
	vim.api.nvim_win_set_cursor(win, { target + 1, 0 })
end

function M.scroll(direction, amount)
	local win = vim.api.nvim_get_current_win()
	local pending = scroll_timers[win]
	if pending then
		pending:stop()
		pending:close()
		scroll_timers[win] = nil
	end
	local key = direction
	if direction == "down" then
		key = "\004"
	elseif direction == "up" then
		key = "\021"
	end
	if key ~= "\004" and key ~= "\021" and key ~= "\006" and key ~= "\002" then
		vim.notify("scroll direction must be up/down or Ctrl-D/U/F/B", vim.log.levels.WARN)
		return
	end
	local count = math.max(1, math.min(tonumber(amount) or vim.v.count1, 500))
	local before = vim.api.nvim_win_call(win, vim.fn.winsaveview)
	local original_cursor = vim.api.nvim_win_get_cursor(win)
	local buf = vim.api.nvim_win_get_buf(win)
	local changedtick = vim.api.nvim_buf_get_changedtick(buf)
	vim.api.nvim_win_call(win, function()
		vim.cmd.normal({ args = { tostring(count) .. key }, bang = true })
	end)
	local after = vim.api.nvim_win_call(win, vim.fn.winsaveview)
	vim.api.nvim_win_call(win, function()
		vim.fn.winrestview(before)
	end)
	local duration = config.scroll_duration
	local steps = math.max(1, math.min(12, math.floor(duration / 10)))
	local delta = after.topline - before.topline
	local step = 0
	local timer = vim.uv.new_timer()
	scroll_timers[win] = timer
	timer:start(
		0,
		math.max(1, math.floor(duration / steps)),
		vim.schedule_wrap(function()
			if scroll_timers[win] ~= timer then
				return
			end
			local cursor = vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_cursor(win) or nil
			if
				not cursor
				or cursor[1] ~= original_cursor[1]
				or cursor[2] ~= original_cursor[2]
				or not vim.api.nvim_buf_is_valid(buf)
				or vim.api.nvim_buf_get_changedtick(buf) ~= changedtick
			then
				scroll_timers[win] = nil
				timer:stop()
				timer:close()
				return
			end
			step = step + 1
			if not vim.api.nvim_win_is_valid(win) or step >= steps then
				if vim.api.nvim_win_is_valid(win) then
					vim.api.nvim_win_call(win, function()
						vim.fn.winrestview(after)
					end)
				end
				scroll_timers[win] = nil
				timer:stop()
				timer:close()
				schedule_refresh(vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) or -1)
				return
			end
			local view = vim.deepcopy(before)
			view.topline = math.max(1, before.topline + math.floor(delta * step / steps))
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_call(win, function()
					vim.fn.winrestview(view)
				end)
			end
		end)
	)
end

local zen_global = { "laststatus", "showtabline" }
local zen_window = { "number", "relativenumber", "signcolumn", "foldcolumn", "statuscolumn", "cursorline" }

function M.zen()
	local tab = vim.api.nvim_get_current_tabpage()
	local state = zen_state
	if state then
		for name, value in pairs(state.global) do
			vim.o[name] = value
		end
		for win, opts in pairs(state.windows) do
			if vim.api.nvim_win_is_valid(win) then
				for name, value in pairs(opts) do
					vim.wo[win][name] = value
				end
			end
		end
		zen_state = nil
		vim.notify("Zen mode off", vim.log.levels.INFO)
		return
	end
	state = { global = {}, windows = {} }
	for _, name in ipairs(zen_global) do
		state.global[name] = vim.o[name]
	end
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
		state.windows[win] = {}
		for _, name in ipairs(zen_window) do
			state.windows[win][name] = vim.wo[win][name]
		end
	end
	zen_state = state
	vim.o.laststatus = 0
	vim.o.showtabline = 0
	for win in pairs(state.windows) do
		if vim.api.nvim_win_is_valid(win) then
			vim.wo[win].number = false
			vim.wo[win].relativenumber = false
			vim.wo[win].signcolumn = "no"
			vim.wo[win].foldcolumn = "0"
			vim.wo[win].statuscolumn = ""
			vim.wo[win].cursorline = false
		end
	end
	vim.notify("Zen mode on", vim.log.levels.INFO)
end

function M.dim()
	dim_enabled = not dim_enabled
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		render_window(win)
	end
	vim.notify("Dim " .. (dim_enabled and "on" or "off"), vim.log.levels.INFO)
end

local function set_diagnostics(enabled, buf)
	if vim.diagnostic.enable then
		if vim.fn.has("nvim-0.10") == 1 then
			vim.diagnostic.enable(enabled, { bufnr = buf })
		elseif enabled then
			vim.diagnostic.enable(buf)
		else
			vim.diagnostic.disable(buf)
		end
	elseif enabled then
		vim.diagnostic.enable(buf)
	else
		vim.diagnostic.disable(buf)
	end
end

function M.toggle(name)
	local buf = vim.api.nvim_get_current_buf()
	local win = vim.api.nvim_get_current_win()
	local current
	if name == "wrap" or name == "spell" or name == "relativenumber" then
		current = not vim.wo[win][name]
		vim.wo[win][name] = current
	elseif name == "diagnostics" then
		current = not (vim.diagnostic.is_enabled and vim.diagnostic.is_enabled({ bufnr = buf }) or false)
		set_diagnostics(current, buf)
	elseif name == "inlay_hints" then
		local enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = buf })
		current = not enabled
		vim.lsp.inlay_hint.enable(current, { bufnr = buf })
	elseif name == "treesitter" then
		current = vim.b[buf].mayon_treesitter_disabled == true
		vim.b[buf].mayon_treesitter_disabled = not current
		if current then
			if not vim.b[buf].mayon_bigfile then
				vim.treesitter.start(buf)
			end
		else
			vim.treesitter.stop(buf)
		end
	else
		vim.notify("Unknown editor toggle: " .. tostring(name), vim.log.levels.WARN)
		return
	end
	vim.notify(name .. (current and " on" or " off"), vim.log.levels.INFO)
end

local function mark_bigfile(buf, path)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	local stat = path and vim.uv.fs_stat(path)
	if not stat or stat.size <= config.bigfile_size then
		return
	end
	vim.b[buf].mayon_bigfile = true
	vim.b[buf].mayon_bigfile_size = stat.size
	vim.bo[buf].indentexpr = ""
	if vim.bo[buf].syntax ~= "" then
		vim.bo[buf].syntax = ""
	end
	local wins = vim.fn.win_findbuf(buf)
	if #wins == 0 and vim.api.nvim_get_current_buf() == buf then
		wins = { vim.api.nvim_get_current_win() }
	end
	for _, win in ipairs(wins) do
		if vim.api.nvim_win_is_valid(win) then
			vim.wo[win].foldmethod = "manual"
			vim.wo[win].foldexpr = "0"
		end
	end
	set_diagnostics(false, buf)
	if vim.treesitter and vim.treesitter.stop then
		pcall(vim.treesitter.stop, buf)
	end
	-- Detach only this buffer; the shared LSP client remains available to other files.
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
		pcall(vim.lsp.buf_detach_client, buf, client.id)
	end
	for _, namespace in pairs(ns) do
		pcall(vim.api.nvim_buf_clear_namespace, buf, namespace, 0, -1)
	end
end

function M.fold_click()
	local mouse = vim.fn.getmousepos()
	if mouse.winid == 0 or mouse.line < 1 or not vim.api.nvim_win_is_valid(mouse.winid) then
		return
	end
	local buf = vim.api.nvim_win_get_buf(mouse.winid)
	local foldable = vim.api.nvim_win_call(mouse.winid, function()
		return vim.fn.foldlevel(mouse.line) > 0
	end)
	if not foldable then
		return
	end
	vim.api.nvim_win_set_cursor(mouse.winid, { mouse.line, 0 })
	vim.api.nvim_win_call(mouse.winid, function()
		vim.cmd.normal({ args = { "za" }, bang = true })
	end)
	schedule_refresh(buf)
end

local function git_sign(name)
	return name and (name:find("GitSign", 1, true) ~= nil or name:find("MiniDiffSign", 1, true) ~= nil)
end

local function sign_parts(buf, lnum)
	local key = buf .. ":" .. lnum
	local cached = status_cache.signs[key]
	if cached then
		return cached
	end
	local result = { regular = nil, git = nil }
	local row = lnum - 1
	local ok, marks = pcall(
		vim.api.nvim_buf_get_extmarks,
		buf,
		-1,
		{ row, 0 },
		{ row + 1, 0 },
		{ details = true, type = "sign" }
	)
	if ok then
		for _, extmark in ipairs(marks) do
			local details = extmark[4] or {}
			local name = details.sign_hl_group or details.sign_name or ""
			local part = {
				text = details.sign_text or "",
				hl = details.sign_hl_group,
				priority = details.priority or 0,
			}
			local field = git_sign(name) and "git" or "regular"
			if not result[field] or part.priority > result[field].priority then
				result[field] = part
			end
		end
	else
		-- Compatibility for Neovim versions where legacy signs are not returned
		-- by nvim_buf_get_extmarks(type="sign").
		local placed_ok, placed = pcall(vim.fn.sign_getplaced, buf, { group = "*", lnum = lnum })
		if placed_ok and placed[1] then
			for _, sign in ipairs(placed[1].signs or {}) do
				local defined = vim.fn.sign_getdefined(sign.name)[1]
				if defined then
					local part = { text = defined.text or "", hl = defined.texthl, priority = sign.priority or 0 }
					local field = git_sign(sign.name) and "git" or "regular"
					if not result[field] or part.priority > result[field].priority then
						result[field] = part
					end
				end
			end
		end
	end
	status_cache.signs[key] = result
	return result
end

local function mark_part(buf, lnum)
	local cached = status_cache.marks[buf]
	if not cached then
		cached = {}
		local all = vim.fn.getmarklist(buf)
		vim.list_extend(all, vim.fn.getmarklist())
		for _, mark in ipairs(all) do
			if mark.pos and mark.pos[1] == buf and mark.pos[2] > 0 and mark.mark and mark.mark:match("^'[A-Za-z]$") then
				cached[mark.pos[2]] = cached[mark.pos[2]] or mark.mark:sub(2)
			end
		end
		status_cache.marks[buf] = cached
	end
	return cached[lnum]
end

local function status_icon(text, hl)
	if not text or text == "" then
		return "  "
	end
	text = vim.fn.strcharpart(text, 0, 2):gsub("%%", "%%%%")
	local width = vim.fn.strdisplaywidth(text)
	if width < 2 then
		text = text .. string.rep(" ", 2 - width)
	end
	return (hl and ("%#" .. hl .. "#") or "") .. text .. (hl and "%*" or "")
end

function M.statuscolumn()
	local win = vim.g.statusline_winid
	if not win or not vim.api.nvim_win_is_valid(win) or vim.v.virtnum ~= 0 then
		return ""
	end
	local buf, lnum = vim.api.nvim_win_get_buf(win), vim.v.lnum
	local number, relative = vim.wo[win].number, vim.wo[win].relativenumber
	local show_signs = vim.wo[win].signcolumn ~= "no"
	local signs = show_signs and sign_parts(buf, lnum) or { regular = nil, git = nil }
	local mark = show_signs and mark_part(buf, lnum) or nil
	local left = mark and status_icon(mark, "DiagnosticHint")
		or status_icon(signs.regular and signs.regular.text, signs.regular and signs.regular.hl)

	local fold
	local closed, open = vim.api.nvim_win_call(win, function()
		return vim.fn.foldclosed(lnum) == lnum, vim.fn.foldlevel(lnum) > vim.fn.foldlevel(math.max(0, lnum - 1))
	end)
	if closed then
		fold = status_icon(vim.opt.fillchars:get().foldclose or "", "Folded")
	elseif open then
		fold = status_icon(vim.opt.fillchars:get().foldopen or "", "Folded")
	end
	local right = fold
		or status_icon(show_signs and signs.git and signs.git.text, show_signs and signs.git and signs.git.hl)
	local absnum = relative and number and vim.v.relnum == 0
	local num = relative and not absnum and vim.v.relnum or vim.v.lnum
	local middle = (number or relative) and ("%=" .. tostring(num) .. " ") or "%="
	local fold_click = fold and ("%@v:lua.MayonStatusFoldClick@" .. fold .. "%T") or "  "
	return left
		.. middle
		.. fold_click
		.. (
			fold
				and status_icon(show_signs and signs.git and signs.git.text, show_signs and signs.git and signs.git.hl)
			or right
		)
end

function M.setup(opts)
	if setup_done then
		return
	end
	setup_done = true
	config = vim.tbl_deep_extend("force", config, opts or {})

	local function apply_highlights()
		vim.api.nvim_set_hl(0, "MayonIndent", { link = "Comment" })
		vim.api.nvim_set_hl(0, "MayonIndentScope", { link = "SpecialComment" })
		vim.api.nvim_set_hl(0, "MayonWord", { link = "LspReferenceText" })
		vim.api.nvim_set_hl(0, "MayonDim", { fg = "#777777" })
	end
	apply_highlights()

	-- Read native mark/sign data, then split it into left marks/diagnostics and
	-- right folds/GitSigns. The fold marker owns the only click target.
	_G.MayonStatusFoldClick = M.fold_click
	_G.MayonStatusColumn = M.statuscolumn
	vim.o.statuscolumn = "%!v:lua.MayonStatusColumn()"
	vim.o.foldenable = true

	local group = vim.api.nvim_create_augroup("MayonNativeEditor", { clear = true })
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		callback = apply_highlights,
	})
	vim.api.nvim_create_autocmd({ "BufReadPre" }, {
		group = group,
		callback = function(args)
			mark_bigfile(args.buf, args.file)
		end,
	})
	vim.api.nvim_create_autocmd({ "BufReadPost", "BufEnter" }, {
		group = group,
		callback = function(args)
			if not vim.b[args.buf].mayon_bigfile then
				mark_bigfile(args.buf, vim.api.nvim_buf_get_name(args.buf))
			end
			schedule_refresh(args.buf)
		end,
	})
	-- Syntax and parser FileType handlers run after BufReadPre. Reapply the
	-- buffer-local guard after those handlers, without stopping shared clients.
	vim.api.nvim_create_autocmd({ "FileType", "Syntax" }, {
		group = group,
		callback = function(args)
			if vim.b[args.buf].mayon_bigfile then
				vim.schedule(function()
					if vim.api.nvim_buf_is_valid(args.buf) then
						mark_bigfile(args.buf, vim.api.nvim_buf_get_name(args.buf))
					end
				end)
			end
		end,
	})

	vim.api.nvim_create_autocmd("LspAttach", {
		group = group,
		callback = function(args)
			if vim.b[args.buf].mayon_bigfile then
				pcall(vim.lsp.buf_detach_client, args.buf, args.data.client_id)
			end
		end,
	})
	vim.api.nvim_create_autocmd(
		{ "CursorMoved", "CursorMovedI", "WinScrolled", "TextChanged", "TextChangedI", "BufWinEnter", "WinResized" },
		{
			group = group,
			callback = function(args)
				schedule_refresh(args.buf or vim.api.nvim_get_current_buf())
			end,
		}
	)
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = group,
		callback = function(args)
			for win, state in pairs(render_states) do
				if state.buf == args.buf then
					render_states[win] = nil
				end
			end
			status_cache.marks[args.buf] = nil
			for key in pairs(status_cache.signs) do
				if key:match("^" .. args.buf .. ":") then
					status_cache.signs[key] = nil
				end
			end
		end,
	})
	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		callback = function(args)
			local win = tonumber(args.match)
			if win then
				render_states[win] = nil
				refresh_pending[win] = nil
			end
		end,
	})
	status_timer = vim.uv.new_timer()
	status_timer:start(50, 50, function()
		status_cache.signs = {}
		status_cache.marks = {}
	end)
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			if status_timer then
				status_timer:stop()
				status_timer:close()
				status_timer = nil
			end
		end,
	})
	vim.api.nvim_create_user_command("MayonToggle", function(args)
		M.toggle(args.args)
	end, {
		nargs = 1,
		complete = function()
			return { "wrap", "spell", "relativenumber", "diagnostics", "inlay_hints", "treesitter" }
		end,
	})

	-- Keep native scrolling behavior: execute the built-in command to compute
	-- its exact target view, then interpolate only the viewport before applying
	-- that final native view. Counts and the command's cursor semantics survive.
	for _, key in ipairs({ "<C-d>", "<C-u>", "<C-f>", "<C-b>" }) do
		local control = vim.api.nvim_replace_termcodes(key, true, false, true)
		vim.keymap.set("n", key, function()
			M.scroll(control)
		end, { desc = "Smooth " .. key .. " scroll", silent = true })
	end
end

return M
