-- Small native replacements for vim.ui and vim.notify.
--
-- This module intentionally uses only Neovim APIs. Its public entry points are
-- setup(), input(), select(), notify(), and history().
local M = {}

local history = {}
local visible = {}
local next_id = 0
local max_history = 100
local max_visible = 4

local level_names = {
	[vim.log.levels.TRACE] = "TRACE",
	[vim.log.levels.DEBUG] = "DEBUG",
	[vim.log.levels.INFO] = "INFO",
	[vim.log.levels.WARN] = "WARN",
	[vim.log.levels.ERROR] = "ERROR",
}

local level_highlights = {
	TRACE = "MayonUINotifyTrace",
	DEBUG = "MayonUINotifyDebug",
	INFO = "MayonUINotifyInfo",
	WARN = "MayonUINotifyWarn",
	ERROR = "MayonUINotifyError",
}

local function set_highlights()
	vim.api.nvim_set_hl(0, "MayonUIFloat", { link = "NormalFloat", default = true })
	vim.api.nvim_set_hl(0, "MayonUIBorder", { link = "FloatBorder", default = true })
	vim.api.nvim_set_hl(0, "MayonUITitle", { link = "FloatTitle", default = true })
	vim.api.nvim_set_hl(0, "MayonUISelect", { link = "Visual", default = true })
	vim.api.nvim_set_hl(0, "MayonUINotifyTrace", { link = "Comment", default = true })
	vim.api.nvim_set_hl(0, "MayonUINotifyDebug", { link = "DiagnosticHint", default = true })
	vim.api.nvim_set_hl(0, "MayonUINotifyInfo", { link = "DiagnosticInfo", default = true })
	vim.api.nvim_set_hl(0, "MayonUINotifyWarn", { link = "DiagnosticWarn", default = true })
	vim.api.nvim_set_hl(0, "MayonUINotifyError", { link = "DiagnosticError", default = true })
end

local function has_ui()
	return #vim.api.nvim_list_uis() > 0
end

local function valid_buf(buf)
	return buf ~= nil and vim.api.nvim_buf_is_valid(buf)
end

local function valid_win(win)
	return win ~= nil and vim.api.nvim_win_is_valid(win)
end

local function truncate_display(text, max_width)
	text = tostring(text or "")
	local count = vim.fn.strchars(text)
	if count <= max_width and vim.fn.strdisplaywidth(text) <= max_width then
		return text
	end
	local result, width = {}, 0
	local truncated = false
	for index = 0, math.min(count, max_width) - 1 do
		local char = vim.fn.strcharpart(text, index, 1)
		local char_width = vim.fn.strdisplaywidth(char)
		if width + char_width > max_width - 1 then
			truncated = true
			break
		end
		result[#result + 1] = char
		width = width + char_width
		if index == math.min(count, max_width) - 1 and count > max_width then
			truncated = true
		end
	end
	return table.concat(result) .. (truncated and "…" or "")
end

local function float_config(width, height, opts)
	local columns = vim.o.columns
	local lines = vim.o.lines
	width = math.max(1, math.min(width, columns - 4))
	height = math.max(1, math.min(height, lines - 4))
	return {
		relative = "editor",
		style = "minimal",
		border = "rounded",
		width = width,
		height = height,
		row = opts.row or math.max(0, math.floor((lines - height) / 2) - 1),
		col = opts.col or math.max(0, math.floor((columns - width) / 2)),
		title = opts.title,
		title_pos = opts.title_pos or "center",
		zindex = opts.zindex or 60,
	}
end

local function open_float(buf, width, height, opts)
	local win = vim.api.nvim_open_win(buf, true, float_config(width, height, opts or {}))
	vim.wo[win].winhighlight = "Normal:MayonUIFloat,FloatBorder:MayonUIBorder,FloatTitle:MayonUITitle"
	vim.wo[win].signcolumn = "no"
	vim.wo[win].wrap = false
	return win
end

local function close_window(win)
	if valid_win(win) then
		pcall(vim.api.nvim_win_close, win, true)
	end
end

local function close_buffer(buf)
	if valid_buf(buf) then
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end
end

local function once_callback(callback)
	local called = false
	return function(...)
		if called then
			return
		end
		called = true
		if callback then
			callback(...)
		end
	end
end

local function cancel_keymaps(buf, finish, confirm)
	vim.keymap.set({ "n", "i" }, "<Esc>", function()
		finish(nil)
	end, { buffer = buf, nowait = true, silent = true })
	vim.keymap.set({ "n", "i" }, "<C-c>", function()
		finish(nil)
	end, { buffer = buf, nowait = true, silent = true })
	vim.keymap.set("n", "q", function()
		finish(nil)
	end, { buffer = buf, nowait = true, silent = true })
	vim.keymap.set({ "n", "i" }, "<CR>", confirm, { buffer = buf, nowait = true, silent = true })
end

_G.MayonUIComplete = _G.MayonUIComplete
	or function(findstart, base)
		local completion = vim.b[vim.api.nvim_get_current_buf()].mayon_ui_completion
		if findstart == 1 then
			local line = vim.api.nvim_get_current_line()
			return #(line:gsub("%S+$", ""))
		end
		if type(completion) ~= "string" or completion == "" then
			return {}
		end
		local ok, matches = pcall(vim.fn.getcompletion, base, completion)
		return ok and matches or {}
	end

local function restore_origin_mode(win, mode)
	if valid_win(win) and vim.api.nvim_get_current_win() ~= win then
		pcall(vim.api.nvim_set_current_win, win)
	end
	if mode:sub(1, 1) == "i" then
		vim.cmd("startinsert")
	elseif mode:sub(1, 1) == "R" then
		vim.cmd("startreplace")
	elseif vim.fn.mode(1):sub(1, 1) == "i" then
		vim.cmd("stopinsert")
	end
end

local function after_restore(win, mode, callback)
	vim.schedule(function()
		restore_origin_mode(win, mode)
		vim.defer_fn(callback, 10)
	end)
end

function M.input(opts, on_confirm)
	opts = opts or {}
	local finish = once_callback(on_confirm)
	if not has_ui() then
		finish(nil)
		return
	end

	local origin_win = vim.api.nvim_get_current_win()
	local origin_mode = vim.fn.mode(1)
	local width = math.max(34, math.min(72, (vim.o.columns or 80) - 8))
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "prompt"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.b[buf].mayon_ui_completion = opts.completion
	vim.bo[buf].completefunc = "v:lua.MayonUIComplete"
	vim.bo[buf].omnifunc = "v:lua.MayonUIComplete"
	vim.fn.prompt_setprompt(buf, "")
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { opts.default or "" })

	local win = open_float(buf, width, 1, {
		title = truncate_display(
			tostring(opts.title or opts.prompt or " Input "):gsub("\n", " "),
			math.max(1, width - 4)
		),
		title_pos = "left",
	})
	vim.api.nvim_win_set_cursor(win, { 1, #(opts.default or "") })
	local closing = false
	vim.wo[win].winhighlight =
		"Normal:MayonUIFloat,FloatBorder:MayonUIBorder,FloatTitle:MayonUITitle,CursorLine:MayonUISelect"
	vim.wo[win].cursorline = false
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win),
		once = true,
		callback = function()
			if not closing then
				closing = true
				after_restore(origin_win, origin_mode, function()
					finish(nil)
				end)
			end
			close_buffer(buf)
		end,
	})

	local function complete(value)
		if closing then
			return
		end
		closing = true
		close_window(win)
		close_buffer(buf)
		after_restore(origin_win, origin_mode, function()
			finish(value)
		end)
	end
	cancel_keymaps(buf, complete, function()
		local value = ""
		if valid_buf(buf) then
			value = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
		end
		complete(value)
	end)
	vim.cmd("startinsert!")
end

local function display_item(item, formatter)
	local ok, value = pcall(formatter, item)
	if not ok then
		value = tostring(item)
	end
	return tostring(value or ""):gsub("\r?\n", " ")
end

function M.select(items, opts, on_choice)
	opts = opts or {}
	local finish = once_callback(on_choice)
	if type(items) ~= "table" or #items == 0 or not has_ui() then
		finish(nil, nil)
		return
	end

	local origin_win = vim.api.nvim_get_current_win()
	local origin_mode = vim.fn.mode(1)
	local formatter = opts.format_item or tostring
	local max_width = math.max(1, math.min(80, vim.o.columns - 6))
	local labels = {}
	local width = math.min(24, max_width)
	for i, item in ipairs(items) do
		labels[i] = truncate_display(display_item(item, formatter), max_width - 2)
		width = math.max(width, vim.fn.strdisplaywidth(labels[i]))
	end
	width = math.min(width + 2, max_width)
	local height = math.min(#labels, math.max(1, vim.o.lines - 8))
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, labels)
	vim.bo[buf].modifiable = false
	vim.bo[buf].filetype = "mayon-select"

	local win = open_float(buf, width, height, {
		title = truncate_display((opts.prompt or opts.kind or " Select "):gsub("\n", " "), math.max(1, width - 4)),
		title_pos = "center",
	})
	local closing = false
	vim.wo[win].cursorline = true
	vim.wo[win].winhighlight =
		"Normal:MayonUIFloat,FloatBorder:MayonUIBorder,FloatTitle:MayonUITitle,CursorLine:MayonUISelect"
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win),
		once = true,
		callback = function()
			if not closing then
				closing = true
				after_restore(origin_win, origin_mode, function()
					finish(nil, nil)
				end)
			end
			close_buffer(buf)
		end,
	})

	local function complete(index)
		if closing then
			return
		end
		closing = true
		close_window(win)
		close_buffer(buf)
		after_restore(origin_win, origin_mode, function()
			if index and items[index] ~= nil then
				finish(items[index], index)
			else
				finish(nil, nil)
			end
		end)
	end
	cancel_keymaps(buf, function()
		complete(nil)
	end, function()
		local row = valid_win(win) and vim.api.nvim_win_get_cursor(win)[1] or 1
		complete(row)
	end)
	for _, key in ipairs({ "j", "<Down>" }) do
		vim.keymap.set("n", key, function()
			local row = vim.api.nvim_win_get_cursor(win)[1]
			vim.api.nvim_win_set_cursor(win, { math.min(#items, row + 1), 0 })
		end, { buffer = buf, nowait = true, silent = true })
	end
	for _, key in ipairs({ "k", "<Up>" }) do
		vim.keymap.set("n", key, function()
			local row = vim.api.nvim_win_get_cursor(win)[1]
			vim.api.nvim_win_set_cursor(win, { math.max(1, row - 1), 0 })
		end, { buffer = buf, nowait = true, silent = true })
	end
end

local function normalize_level(level)
	if type(level) == "string" then
		local upper = level:upper()
		for number, name in pairs(level_names) do
			if name == upper then
				return number, name
			end
		end
	end
	level = tonumber(level) or vim.log.levels.INFO
	return level, level_names[level] or "INFO"
end

local function stringify(message)
	if type(message) == "string" then
		return message
	end
	if type(message) == "table" then
		return table.concat(vim.tbl_map(tostring, message), "\n")
	end
	return tostring(message)
end

local function history_index(id)
	for index, entry in ipairs(history) do
		if entry.id == id then
			return index
		end
	end
end

local function notification_lines(entry)
	local lines = vim.split(truncate_display(entry.message, 4096), "\n", { plain = true })
	if #lines == 0 then
		lines = { "" }
	end
	if #lines > 6 then
		local remaining = #lines - 5
		for index = #lines, 6, -1 do
			table.remove(lines, index)
		end
		lines[6] = string.format("… (%d more lines)", remaining)
	end
	return lines
end

local function notification_width(columns)
	return math.max(1, math.min(58, columns - 6))
end

local function notification_title(entry, width)
	return truncate_display(
		string.format(" %s · %s ", entry.level_name, entry.title or "Neovim"),
		math.max(1, width - 4)
	)
end

local close_notification

local function redraw_notifications()
	if not has_ui() then
		return
	end
	local row = 1
	local columns = vim.o.columns
	local screen_lines = vim.o.lines
	local slots = math.max(1, math.min(max_visible, math.floor((screen_lines - 3) / 3)))
	while #visible > slots do
		close_notification(visible[#visible], true)
	end
	local height_limit = math.max(1, math.floor((screen_lines - 4) / slots) - 2)
	for index, entry in ipairs(visible) do
		if valid_win(entry.win) and valid_buf(entry.buf) then
			local width = notification_width(columns)
			local lines = notification_lines(entry)
			local height = math.min(math.max(1, #lines), 6, height_limit)
			local config = {
				relative = "editor",
				style = "minimal",
				border = "rounded",
				width = width,
				height = height,
				row = row,
				col = math.max(0, columns - width - 2),
				title = notification_title(entry, width),
				title_pos = "left",
				zindex = 80 + index,
			}
			pcall(vim.api.nvim_win_set_config, entry.win, config)
			vim.wo[entry.win].winhighlight = "Normal:MayonUIFloat,FloatBorder:"
				.. (level_highlights[entry.level_name] or "MayonUIBorder")
			row = row + height + 2
		end
	end
end

close_notification = function(entry, skip_redraw)
	if entry.closing then
		return
	end
	entry.closing = true
	if entry.timer then
		entry.timer:stop()
		entry.timer:close()
		entry.timer = nil
	end
	close_window(entry.win)
	close_buffer(entry.buf)
	entry.win, entry.buf = nil, nil
	for index, item in ipairs(visible) do
		if item == entry then
			table.remove(visible, index)
			break
		end
	end
	if not skip_redraw then
		redraw_notifications()
	end
end

function M.notify(message, level, opts)
	opts = opts or {}
	local numeric_level, level_name = normalize_level(level or opts.level)
	local text = message == nil and "" or truncate_display(stringify(message), 8192)
	local replace_id = opts.id or opts.replace
	if opts.id == nil and type(replace_id) == "table" then
		replace_id = replace_id.id
	end
	local index = replace_id and history_index(replace_id) or nil
	local entry
	if index then
		entry = history[index]
		close_notification(entry)
		entry.message = text
		entry.level = numeric_level
		entry.level_name = level_name
		entry.title = opts.title and truncate_display(tostring(opts.title):gsub("\n", " "), 48) or entry.title
		entry.updated = os.time()
	else
		next_id = next_id + 1
		entry = {
			id = opts.id or next_id,
			message = text,
			level = numeric_level,
			level_name = level_name,
			title = opts.title and truncate_display(tostring(opts.title):gsub("\n", " "), 48) or nil,
			created = os.time(),
		}
		if opts.history ~= false then
			history[#history + 1] = entry
			while #history > max_history do
				local oldest = table.remove(history, 1)
				close_notification(oldest)
			end
		end
	end
	entry.closing = false

	if has_ui() then
		local buf = vim.api.nvim_create_buf(false, true)
		vim.bo[buf].buftype = "nofile"
		vim.bo[buf].bufhidden = "wipe"
		vim.bo[buf].swapfile = false
		vim.bo[buf].modifiable = true
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, notification_lines(entry))
		vim.bo[buf].modifiable = false
		entry.buf = buf
		entry.win = vim.api.nvim_open_win(buf, false, {
			relative = "editor",
			style = "minimal",
			border = "rounded",
			width = notification_width(vim.o.columns),
			height = math.max(1, math.min(#notification_lines(entry), 6, vim.o.lines - 4)),
			row = 1,
			col = math.max(0, vim.o.columns - notification_width(vim.o.columns) - 2),
			title = notification_title(entry, notification_width(vim.o.columns)),
			title_pos = "left",
			zindex = 90,
		})
		vim.wo[entry.win].wrap = true
		vim.wo[entry.win].winhighlight = "Normal:MayonUIFloat,FloatBorder:"
			.. (level_highlights[level_name] or "MayonUIBorder")
		vim.api.nvim_create_autocmd("WinClosed", {
			pattern = tostring(entry.win),
			once = true,
			callback = function()
				if not entry.closing then
					close_notification(entry)
				end
			end,
		})
		table.insert(visible, 1, entry)
		while #visible > max_visible do
			close_notification(visible[#visible])
		end
		redraw_notifications()
	end

	local timeout = opts.timeout
	if timeout == nil or timeout == true then
		timeout = 2500
	end
	if timeout ~= false and tonumber(timeout) and tonumber(timeout) > 0 then
		entry.timer = vim.uv.new_timer()
		entry.timer:start(tonumber(timeout), 0, function()
			vim.schedule(function()
				close_notification(entry)
			end)
		end)
	end
	return entry.id
end

function M.history()
	if not has_ui() then
		return history
	end

	local lines = {}
	for index = #history, 1, -1 do
		local entry = history[index]
		local title = entry.title and (" · " .. entry.title) or ""
		local message = truncate_display(entry.message:gsub("\n", "  "), 2000)
		lines[#lines + 1] = string.format("[%s]%s %s", entry.level_name, title, message)
	end
	if #lines == 0 then
		lines[1] = "No notifications yet"
	end
	local width = math.min(100, math.max(36, vim.o.columns - 8))
	local height = math.min(#lines, math.max(1, vim.o.lines - 6))
	local origin_win = vim.api.nvim_get_current_win()
	local origin_mode = vim.fn.mode(1)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	local win = open_float(buf, width, height, { title = " Notification history ", title_pos = "center" })
	vim.wo[win].wrap = true
	vim.wo[win].cursorline = true
	local closing = false
	local function close_history()
		if closing then
			return
		end
		closing = true
		close_window(win)
		close_buffer(buf)
		after_restore(origin_win, origin_mode, function() end)
	end
	vim.api.nvim_create_autocmd("WinClosed", {
		pattern = tostring(win),
		once = true,
		callback = function()
			if not closing then
				closing = true
				close_buffer(buf)
				after_restore(origin_win, origin_mode, function() end)
			end
		end,
	})
	vim.keymap.set("n", "q", function()
		close_history()
	end, { buffer = buf, nowait = true, silent = true })
	vim.keymap.set("n", "<Esc>", function()
		close_history()
	end, { buffer = buf, nowait = true, silent = true })
	return win
end

function M.dismiss()
	local pending = {}
	for _, entry in ipairs(visible) do
		pending[#pending + 1] = entry
	end
	for _, entry in ipairs(pending) do
		close_notification(entry, true)
	end
	redraw_notifications()
end

function M.setup()
	set_highlights()
	local group = vim.api.nvim_create_augroup("MayonUI", { clear = true })
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		callback = set_highlights,
	})
	vim.api.nvim_create_autocmd("VimResized", {
		group = group,
		callback = redraw_notifications,
	})
	vim.ui.input = M.input
	vim.ui.select = M.select
	vim.notify = M.notify
end

return M
