-- Native splits keep the tools usable with mouse, keyboard and screen readers.
local M = { rails = {}, headers = {}, enabled = true }
M.rails_by_tab = {}
local function current_rails()
	local tab = vim.api.nvim_get_current_tabpage()
	M.rails_by_tab[tab] = M.rails_by_tab[tab] or {}
	M.rails = M.rails_by_tab[tab]
end
local ns = vim.api.nvim_create_namespace("MayonWorkspace")
local function buffer_labels(buffers)
	local paths, counts, suffix_counts = {}, {}, {}
	for _, buf in ipairs(buffers) do
		local name = vim.api.nvim_buf_get_name(buf)
		local parts = name == "" and {} or vim.split(vim.fn.fnamemodify(name, ":~:."), "/", { trimempty = true })
		paths[buf] = parts
		local base = parts[#parts] or "[No Name]"
		counts[base] = (counts[base] or 0) + 1
	end
	for _, parts in pairs(paths) do
		local suffix = ""
		for i = #parts, 1, -1 do
			suffix = suffix == "" and parts[i] or (parts[i] .. "/" .. suffix)
			suffix_counts[suffix] = (suffix_counts[suffix] or 0) + 1
		end
	end
	local labels = {}
	for _, buf in ipairs(buffers) do
		local parts = paths[buf]
		local base = parts[#parts] or "[No Name]"
		local label = base
		if counts[base] > 1 then
			if #parts == 0 then
				label = base .. " #" .. buf
			else
				for i = #parts - 1, 1, -1 do
					label = parts[i] .. "/" .. label
					if suffix_counts[label] == 1 then
						break
					end
				end
				if suffix_counts[label] ~= 1 then
					label = label .. " #" .. buf
				end
			end
		end
		labels[buf] = label
	end
	return labels
end
M.buffer_labels = buffer_labels
local items = {
	{ "󰉋", "Project", "project" },
	{ "󰊢", "Commit", "commit" },
	{ "󰙅", "Structure", "structure" },
	{ "󰃀", "Bookmarks", "marks" },
	{ "", "Terminal", "terminal" },
	{ "󰅚", "Problems", "problems" },
	{ "󰋚", "History", "history" },
}
local function document(win)
	if not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_config(win).relative ~= "" then
		return false
	end
	local b = vim.api.nvim_win_get_buf(win)
	return vim.bo[b].buftype == "" and vim.bo[b].filetype ~= "" and vim.bo[b].filetype ~= "snacks_dashboard"
end
function M.in_cmdwin()
	return vim.fn.getcmdwintype() ~= ""
end
function M.editor()
	local current = vim.api.nvim_get_current_win()
	if document(current) then
		return current
	end
	for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if document(w) then
			return w
		end
	end
end
function M.action(name)
	local S = require("snacks")
	local editor = M.editor()
	if editor then
		vim.api.nvim_set_current_win(editor)
	end
	if name == "project" then
		S.explorer({ focus = "list" })
	elseif name == "commit" then
		vim.cmd.Neogit()
	elseif name == "structure" then
		require("lz.n").trigger_load("aerial.nvim")
		require("aerial").toggle({ focus = true })
	elseif name == "marks" then
		S.picker.marks()
	elseif name == "terminal" then
		S.terminal(nil, { win = { position = "bottom", height = 0.25 } })
	elseif name == "problems" then
		vim.cmd("Trouble diagnostics toggle")
	elseif name == "history" then
		vim.cmd("CodeDiff history")
	elseif name == "ai" then
		vim.cmd("CodeCompanionChat Toggle")
	elseif name == "notifications" then
		S.notifier.show_history()
	elseif name == "tasks" then
		require("mayon.features.tasks").pick()
	end
	M.active = name
	M.refresh()
end
function M.page(editor, direction)
	local header = M.headers[editor]
	if not header then
		return
	end
	if direction == "pick" then
		require("lz.n").trigger_load("snacks.nvim")
		require("snacks").picker.buffers()
		return
	end
	local delta = direction == "next" and math.max(1, header.page_count or 1) or -math.max(1, header.page_count or 1)
	header.page_start = math.max(1, (header.page_start or 1) + delta)
	M.refresh()
end
local function split(ft, side, size, target)
	local b = vim.api.nvim_create_buf(false, true)
	vim.bo[b].bufhidden = "wipe"
	vim.bo[b].filetype = ft
	local config = { split = side, win = target, style = "minimal" }
	if side == "left" or side == "right" then
		config.width = size
	else
		config.height = size
	end
	local w = vim.api.nvim_open_win(b, false, config)
	for k, v in pairs({
		number = false,
		relativenumber = false,
		signcolumn = "no",
		foldcolumn = "0",
		cursorline = false,
		winfixwidth = true,
		winfixheight = true,
		winbar = "",
		statuscolumn = "",
		wrap = false,
		fillchars = "eob: ,vert: ,horiz: ",
		winhighlight = "Normal:MayonToolRail,NormalNC:MayonToolRail,EndOfBuffer:MayonToolRail,WinSeparator:MayonFrame",
	}) do
		vim.wo[w][k] = v
	end
	return w, b
end
local function setlines(buf, lines)
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
end
local function rail(side, target)
	local w, b = split("mayon_tools", side, 3, target)
	M.rails[side] = { win = w, buf = b, actions = {} }
	vim.keymap.set("n", "<LeftMouse>", function()
		local pos = vim.fn.getmousepos()
		local rail = M.rails[side]
		local action = rail and rail.actions[pos.line]
		if action then
			M.action(action)
		end
	end, { buffer = b, desc = "打开工具窗口" })
	vim.keymap.set("n", "<CR>", function()
		local action = M.rails[side].actions[vim.fn.line(".")]
		if action then
			M.action(action)
		end
	end, { buffer = b, desc = "打开工具窗口" })
end
function M.refresh()
	current_rails()
	for side, r in pairs(M.rails) do
		if vim.api.nvim_win_is_valid(r.win) then
			local height = vim.api.nvim_win_get_height(r.win)
			local lines = {}
			r.actions = {}
			for i = 1, height do
				lines[i] = "   "
			end
			local choices = side == "left" and items
				or {
					{ "󰚩", "AI", "ai" },
					{ "󰂚", "Notifications", "notifications" },
					{
						"󰙅",
						"Structure",
						"structure",
					},
				}
			for i, item in ipairs(choices) do
				local row = i <= 4 and (i * 2 - 1) or math.max(9, height - (#choices - i) * 2 - 1)
				if row <= height then
					lines[row] = " " .. item[1]
					r.actions[row] = item[3]
				end
			end
			setlines(r.buf, lines)
			for row, action in pairs(r.actions) do
				vim.api.nvim_buf_set_extmark(
					r.buf,
					ns,
					row - 1,
					0,
					{ line_hl_group = action == M.active and "MayonToolRailActive" or "MayonToolRail" }
				)
			end
		end
	end
	local active = require("mayon.ui.tabline").active_buffer()
	for editor, h in pairs(M.headers) do
		if vim.api.nvim_win_is_valid(editor) and vim.api.nvim_win_is_valid(h.win) then
			local width = vim.api.nvim_win_get_width(h.win)
			local text = ""
			local spans = {}
			h.ranges = {}
			local tabline = require("mayon.ui.tabline")
			local buffers = {}
			for _, b in ipairs(tabline.buffers()) do
				if vim.bo[b].buftype == "" or vim.bo[b].buftype == "acwrite" then
					buffers[#buffers + 1] = b
				end
			end
			local labels = buffer_labels(buffers)
			local others = {}
			for _, b in ipairs(buffers) do
				if b ~= active then
					others[#others + 1] = b
				end
			end
			if h.active_buf ~= active then
				h.active_buf, h.page_start = active, 1
			end
			local text_width = function(value)
				return vim.fn.strwidth(value)
			end
			-- First try the full row. When it does not fit, pin the active document
			-- and page through the remaining buffers in a separate, stable sequence.
			local function compose(start_at, paged)
				text, spans, h.ranges = "", {}, {}
				local reserve = paged and math.min(width, 6) or 0
				local limit = width - reserve
				local function put(buf)
					local path = vim.api.nvim_buf_get_name(buf)
					local icon, hl = require("mayon.ui.icons").get(path)
					local marker = vim.bo[buf].modified and " ● " or " × "
					local available = limit - text_width(text) - text_width(" " .. icon .. marker)
					if available < 2 and buf ~= active then
						return false
					end
					local label =
						require("mayon.ui.text").fit(labels[buf] or "Untitled", math.max(1, math.min(28, available)))
					local start = #text
					local value = " " .. icon .. label .. marker
					local left = text_width(text)
					text = text .. value
					local right = text_width(text)
					h.ranges[#h.ranges + 1] = { left = left + 1, right = right, buf = buf }
					spans[#spans + 1] = {
						start = start,
						finish = #text,
						iconhl = hl,
						iconend = start + 1 + #icon,
						active = buf == active,
						modified = vim.bo[buf].modified,
					}
					return true
				end
				if active and vim.api.nvim_buf_is_valid(active) then
					put(active)
				end
				local rendered = 0
				for index = start_at, #others do
					if not put(others[index]) then
						break
					end
					rendered = rendered + 1
				end
				return rendered
			end
			local rendered = compose(1, false)
			local overflow = rendered < #others
			if overflow then
				h.page_start = math.max(1, math.min(h.page_start or 1, math.max(1, #others)))
				rendered = compose(h.page_start, true)
				h.page_count = rendered
				local prev = h.page_start > 1
				local next_at = h.page_start + rendered
				local more = next_at <= #others
				local suffix = (more and " ›" or "  ") .. " ⋯"
				local prefix = (prev and "‹ " or "  ")
				local before_suffix = prefix .. text
				local padding = string.rep(" ", math.max(0, width - text_width(before_suffix .. suffix)))
				local suffix_column = text_width(before_suffix .. padding)
				text = before_suffix .. padding .. suffix
				for _, range in ipairs(h.ranges) do
					range.left = range.left + text_width(prefix)
					range.right = range.right + text_width(prefix)
				end
				for _, span in ipairs(spans) do
					span.start = span.start + #prefix
					span.finish = span.finish + #prefix
					span.iconend = span.iconend + #prefix
				end
				h.controls = {
					{ left = 1, right = prev and 1 or 2, action = prev and "previous" or "picker" },
					{ left = suffix_column + 4, right = suffix_column + 4, action = "picker" },
				}
				if more then
					h.controls[#h.controls + 1] =
						{ left = suffix_column + 2, right = suffix_column + 2, action = "next" }
				end
			else
				h.controls = {}
				h.page_count = #others
			end
			setlines(h.buf, { text })
			for _, s in ipairs(spans) do
				vim.api.nvim_buf_set_extmark(
					h.buf,
					ns,
					0,
					s.start,
					{ end_col = s.finish, hl_group = s.active and "TabLineSel" or "TabLine" }
				)
				if s.iconhl then
					vim.api.nvim_buf_set_extmark(
						h.buf,
						ns,
						0,
						s.start + 1,
						{ end_col = s.iconend, hl_group = s.iconhl }
					)
				end
				if s.modified then
					vim.api.nvim_buf_set_extmark(
						h.buf,
						ns,
						0,
						s.finish - 5,
						{ end_col = s.finish, hl_group = "MayonModified" }
					)
				end
			end
			if overflow then
				local prefix = h.page_start > 1 and "‹ " or "  "
				vim.api.nvim_buf_set_extmark(h.buf, ns, 0, 0, { end_col = #prefix, hl_group = "Comment" })
			end
		end
	end
	vim.cmd.redrawtabline()
end
function M.cleanup()
	local had = false
	for editor, h in pairs(M.headers) do
		if not vim.api.nvim_win_is_valid(editor) or not document(editor) then
			had = true
			if vim.api.nvim_win_is_valid(h.win) and #vim.api.nvim_tabpage_list_wins(0) > 1 then
				pcall(vim.api.nvim_win_close, h.win, true)
			end
			M.headers[editor] = nil
		end
	end
	if had and not M.editor() then
		local keep
		for _, r in pairs(M.rails) do
			if vim.api.nvim_win_is_valid(r.win) then
				keep = r.win
				break
			end
		end
		if keep then
			vim.api.nvim_win_set_buf(keep, vim.api.nvim_create_buf(true, false))
			vim.wo[keep].winfixwidth = false
			vim.wo[keep].winfixheight = false
			vim.wo[keep].winhighlight = ""
			for _, r in pairs(M.rails) do
				if r.win ~= keep and vim.api.nvim_win_is_valid(r.win) then
					pcall(vim.api.nvim_win_close, r.win, true)
				end
			end
			M.rails = {}
			M.rails_by_tab[vim.api.nvim_get_current_tabpage()] = M.rails
			vim.api.nvim_set_current_win(keep)
			require("snacks").dashboard()
		end
	end
end
function M.attach()
	if M.in_cmdwin() then
		return
	end
	current_rails()
	M.cleanup()
	if not M.enabled then
		return
	end
	local editor = M.editor()
	if not editor then
		return
	end
	local current = vim.api.nvim_get_current_win()
	for _, side in ipairs({ "left", "right" }) do
		if not M.rails[side] or not vim.api.nvim_win_is_valid(M.rails[side].win) then
			rail(side, side == "left" and -1 or -1)
		end
	end
	if not M.headers[editor] or not vim.api.nvim_win_is_valid(M.headers[editor].win) then
		local w, b = split("mayon_tabs", "above", 1, editor)
		vim.wo[w].winhighlight = "Normal:TabLineFill,NormalNC:TabLineFill,WinSeparator:MayonFrame"
		M.headers[editor] = { win = w, buf = b }
		vim.keymap.set("n", "<LeftMouse>", function()
			local pos = vim.fn.getmousepos()
			for _, control in ipairs(M.headers[editor].controls or {}) do
				if pos.column >= control.left and pos.column <= control.right then
					M.page(
						editor,
						control.action == "next" and "next" or control.action == "previous" and "previous" or "pick"
					)
					return
				end
			end
			for _, r in ipairs(M.headers[editor].ranges or {}) do
				if pos.column >= r.left and pos.column <= r.right then
					if not vim.bo[r.buf].modified and pos.column >= r.right - 1 then
						require("snacks").bufdelete({ buf = r.buf })
					else
						require("mayon.ui.tabline").select(r.buf)
					end
					break
				end
			end
		end, { buffer = b, desc = "切换或关闭标签" })
	end
	if vim.api.nvim_win_is_valid(current) then
		vim.api.nvim_set_current_win(current)
	end
	for side, r in pairs(M.rails) do
		if vim.api.nvim_win_is_valid(r.win) then
			local pos = vim.api.nvim_win_get_position(r.win)[2]
			if
				(side == "left" and pos ~= 0)
				or (side == "right" and pos + vim.api.nvim_win_get_width(r.win) < vim.o.columns)
			then
				vim.api.nvim_win_call(r.win, function()
					vim.cmd("wincmd " .. (side == "left" and "H" or "L"))
				end)
			end
			vim.api.nvim_win_set_width(r.win, 3)
		end
	end
	for _, h in pairs(M.headers) do
		if vim.api.nvim_win_is_valid(h.win) then
			vim.api.nvim_win_set_height(h.win, 1)
		end
	end
	M.refresh()
end
function M.narrow()
	if vim.o.columns >= 140 then
		return
	end
	for _, p in ipairs(require("snacks").picker.get({ source = "explorer" })) do
		p:close()
	end
	if package.loaded.aerial then
		require("aerial").close()
	end
	if package.loaded.edgy then
		require("edgy").close("right")
	end
end
function M.setup()
	if M.ready then
		return
	end
	M.ready = true
	local pending = false
	local function update()
		if M.in_cmdwin() then
			return
		end
		if pending then
			return
		end
		pending = true
		vim.schedule(function()
			pending = false
			if not vim.g.mayon_session_saving then
				M.attach()
			end
		end)
	end
	vim.api.nvim_create_autocmd(
		{ "BufEnter", "WinEnter", "BufModifiedSet", "VimResized", "WinClosed", "TabEnter" },
		{ callback = update }
	)
	vim.api.nvim_create_autocmd("VimResized", { callback = M.narrow })
	update()
end
return M
