-- Native buffer labels and tab-page controls. Rendering only reads editor state.
local M = {}
local api = vim.api
local names, icons = {}, {}
local dirty, pending, ready = true, false, false
local first, previous_buffer, manual_scroll = 1, nil, false

local function width(value)
	return vim.fn.strdisplaywidth(value)
end

local function safe(value)
	return tostring(value):gsub("[\r\n\t]", " ")
end

local function escape(value)
	return safe(value):gsub("%%", "%%%%")
end

local function clip(value, limit, tail)
	value = safe(value)
	if width(value) <= limit then
		return value
	end
	if limit <= 1 then
		return limit == 1 and "…" or ""
	end
	local chars, result = vim.fn.strchars(value), ""
	for step = 0, chars - 1 do
		local index = tail and chars - step - 1 or step
		local char = vim.fn.strcharpart(value, index, 1)
		if width(result .. char) > limit - 1 then
			break
		end
		result = tail and char .. result or result .. char
	end
	return tail and "…" .. result or result .. "…"
end

local function buffers()
	local result = {}
	for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
		if api.nvim_buf_is_valid(info.bufnr) then
			result[#result + 1] = info.bufnr
		end
	end
	return result
end

local function refresh_names(list)
	local paths, counts, suffixes = {}, {}, {}
	for _, buf in ipairs(list) do
		local filename = api.nvim_buf_get_name(buf)
		local parts = filename == "" and {}
			or vim.split(vim.fn.fnamemodify(filename, ":~:."), "/", { trimempty = true })
		local basename = parts[#parts] or "[No Name]"
		paths[buf] = { parts = parts, basename = basename }
		counts[basename] = (counts[basename] or 0) + 1
		local suffix = ""
		for index = #parts, 1, -1 do
			suffix = parts[index] .. (suffix == "" and "" or "/" .. suffix)
			suffixes[suffix] = (suffixes[suffix] or 0) + 1
		end
	end
	names = {}
	for _, buf in ipairs(list) do
		local item = paths[buf]
		local label, duplicate = item.basename, counts[item.basename] > 1
		if duplicate then
			for index = #item.parts - 1, 1, -1 do
				label = item.parts[index] .. "/" .. label
				if suffixes[label] == 1 then
					break
				end
			end
			if #item.parts == 0 or suffixes[label] ~= 1 then
				label = label .. " #" .. buf
			end
		end
		names[buf] = { label = safe(label), duplicate = duplicate }
	end
	dirty = false
end

local function highlight(name)
	return api.nvim_get_hl(0, { name = name, link = false })
end

local function refresh_icons(list)
	icons = {}
	local ok, devicons = pcall(require, "nvim-web-devicons")
	if not ok then
		return
	end
	local regular, selected = highlight("TabLine"), highlight("TabLineSel")
	for _, buf in ipairs(list) do
		local filename = api.nvim_buf_get_name(buf)
		local glyph, color = devicons.get_icon_color(filename, vim.fn.fnamemodify(filename, ":e"), { default = true })
		if glyph then
			local suffix = tostring(color or regular.fg or ""):gsub("[^%w]", "")
			local base = "MayonTabIcon" .. suffix
			api.nvim_set_hl(0, base, { fg = color or regular.fg, bg = regular.bg })
			api.nvim_set_hl(0, base .. "Sel", { fg = color or selected.fg, bg = selected.bg, bold = true })
			icons[buf] = { glyph = glyph, group = base }
		end
	end
end

local function refresh()
	if pending then
		return
	end
	pending = true
	vim.schedule(function()
		pending = false
		-- BufDelete fires before the buffer leaves the listed set.
		dirty = true
		refresh_icons(buffers())
		vim.cmd.redrawtabline()
	end)
end

local function current_window()
	local win = api.nvim_get_current_win()
	if api.nvim_win_get_config(win).relative == "" then
		return win
	end
	for _, candidate in ipairs(api.nvim_tabpage_list_wins(0)) do
		if api.nvim_win_get_config(candidate).relative == "" then
			return candidate
		end
	end
	return win
end

function M.click(buf, _, button)
	vim.schedule(function()
		if not api.nvim_buf_is_valid(buf) then
			return
		end
		if button == "m" then
			require("mayon.files").bufdelete({ buf = buf })
		elseif button == "l" then
			local win = current_window()
			local ok, err = pcall(api.nvim_win_set_buf, win, buf)
			if ok then
				api.nvim_set_current_win(win)
			else
				vim.notify(tostring(err), vim.log.levels.WARN, { title = "Buffer switch" })
			end
		end
		refresh()
	end)
end

function M.close(buf)
	M.click(buf, 1, "m")
end

function M.scroll(direction, _, button)
	if button ~= "l" then
		return
	end
	first = math.max(1, math.min(#buffers(), first + (direction == 1 and -1 or 1)))
	manual_scroll = true
	refresh()
end

local function pages(limit)
	local tabs = api.nvim_list_tabpages()
	if #tabs < 2 then
		return "", 0
	end
	local current = api.nvim_get_current_tabpage()
	local labels, count, current_index = {}, 3, 1
	for index, tab in ipairs(tabs) do
		local text = " " .. index .. " "
		labels[index] = {
			raw = "%#" .. (tab == current and "TabLineSel" or "TabLine") .. "#%" .. index .. "T" .. text .. "%T",
			width = width(text),
		}
		count = count + width(text)
		if tab == current then
			current_index = index
		end
	end
	local low, high = 1, #tabs
	while count > limit and low < high do
		if current_index - low >= high - current_index then
			count = count - labels[low].width
			low = low + 1
		else
			count = count - labels[high].width
			high = high - 1
		end
	end
	local result, size = {}, 3
	if low > 1 then
		result[#result + 1] = "%" .. (low - 1) .. "T‹%T"
		size = size + 1
	end
	for index = low, high do
		result[#result + 1] = labels[index].raw
		size = size + labels[index].width
	end
	if high < #tabs then
		result[#result + 1] = "%" .. (high + 1) .. "T›%T"
		size = size + 1
	end
	result[#result + 1] = "%#TabLine#%999X × %X"
	return table.concat(result), size
end

local function entry(buf, available)
	local active = buf == api.nvim_get_current_buf()
	local visible = #vim.fn.win_findbuf(buf) > 0
	local base = active and "TabLineSel" or (visible and "MayonTabVisible" or "TabLine")
	local name = names[buf] or { label = "[No Name]" }
	local flags = (vim.bo[buf].modified and " ●" or "")
		.. ((vim.bo[buf].readonly or not vim.bo[buf].modifiable) and " 󰌾" or "")
	local icon = icons[buf]
	local glyph = icon and (icon.glyph .. " ") or ""
	local fixed = width(glyph .. flags .. "  × ")
	if available < fixed + 1 then
		glyph = ""
		fixed = width(flags .. "  × ")
	end
	if available < fixed + 1 then
		flags = ""
		fixed = width("  × ")
	end
	local max_name = math.max(1, available - fixed)
	if not name.duplicate then
		max_name = math.min(28, max_name)
	end
	local label = clip(name.label, max_name, name.duplicate)
	if name.duplicate and width(name.label) > max_name then
		local suffix = " #" .. buf
		label = clip(name.label, math.max(0, max_name - width(suffix)), true) .. suffix
	end
	local content = "%#" .. base .. "#%" .. buf .. "@v:lua.MayonBufferClick@ "
	if glyph ~= "" then
		content = content .. "%#" .. icon.group .. (active and "Sel" or "") .. "#" .. glyph .. "%#" .. base .. "#"
	end
	if visible then
		content = content .. "%#" .. (active and "TabLineSel" or "MayonTabVisible") .. "#"
	end
	content = content .. escape(label)
	if flags:find("●", 1, true) then
		content = content .. "%#MayonTabModified" .. (active and "Sel" or "") .. "# ●%#" .. base .. "#"
	end
	if flags:find("󰌾", 1, true) then
		content = content .. "%#MayonTabLocked" .. (active and "Sel" or "") .. "# 󰌾%#" .. base .. "#"
	end
	content = content .. "%T %" .. buf .. "@v:lua.MayonBufferClose@×%T%#" .. base .. "# "
	return { raw = content, width = width(" " .. glyph .. label .. flags .. " × ") }
end

function M.render()
	local list = buffers()
	if dirty then
		refresh_names(list)
	end
	local tabpages, page_width = pages(math.max(8, math.floor(vim.o.columns / 3)))
	local budget = math.max(1, vim.o.columns - page_width)
	if #list == 0 then
		return "%#TabLineFill#%=" .. tabpages
	end
	local selected, current = 1, api.nvim_get_current_buf()
	for index, buf in ipairs(list) do
		if buf == current then
			selected = index
			break
		end
	end
	if current ~= previous_buffer then
		manual_scroll = false
		previous_buffer = current
	end
	first = math.max(1, math.min(first, #list))
	local available = math.max(1, budget - 6)
	local items = {}
	for index, buf in ipairs(list) do
		items[index] = entry(buf, available)
	end
	local function last_visible(start)
		local last, used = start - 1, 0
		for index = start, #list do
			if used + items[index].width > available and last >= start then
				break
			end
			last, used = index, used + items[index].width
		end
		return last
	end
	local last = last_visible(first)
	if not manual_scroll and (selected < first or selected > last) then
		first = selected
		local used = items[selected].width
		while first > 1 and used + items[first - 1].width <= available do
			first = first - 1
			used = used + items[first].width
		end
		last = last_visible(first)
	end
	local result = { "%#TabLineFill#" }
	if first > 1 then
		result[#result + 1] = "%1@v:lua.MayonBufferScroll@ ‹ %T"
	end
	for index = first, last do
		result[#result + 1] = items[index].raw
	end
	if last < #list then
		result[#result + 1] = "%#TabLine#%2@v:lua.MayonBufferScroll@ › %T"
	end
	result[#result + 1] = "%#TabLineFill#%=" .. tabpages
	return table.concat(result)
end

function M.setup()
	if ready then
		return
	end
	ready = true
	local function colors()
		local regular = highlight("TabLine")
		api.nvim_set_hl(0, "MayonTabVisible", { fg = regular.fg, bg = regular.bg, bold = true })
		api.nvim_set_hl(0, "MayonTabModified", { fg = highlight("String").fg, bg = regular.bg })
		api.nvim_set_hl(0, "MayonTabLocked", { fg = highlight("Constant").fg, bg = regular.bg })
		local selected = highlight("TabLineSel")
		api.nvim_set_hl(0, "MayonTabModifiedSel", { fg = highlight("String").fg, bg = selected.bg, bold = true })
		api.nvim_set_hl(0, "MayonTabLockedSel", { fg = highlight("Constant").fg, bg = selected.bg, bold = true })
	end
	colors()
	refresh_icons(buffers())
	_G.MayonTabline = M.render
	_G.MayonBufferClick = M.click
	_G.MayonBufferClose = M.close
	_G.MayonBufferScroll = M.scroll
	vim.o.tabline = "%!v:lua.MayonTabline()"
	local group = api.nvim_create_augroup("MayonTabline", { clear = true })
	api.nvim_create_autocmd({
		"BufAdd",
		"BufDelete",
		"BufWipeout",
		"BufFilePost",
		"DirChanged",
		"BufEnter",
		"BufWinEnter",
		"BufModifiedSet",
		"WinClosed",
		"TabEnter",
		"TabClosed",
		"TabNew",
	}, {
		group = group,
		callback = function()
			dirty = true
			refresh()
		end,
	})
	api.nvim_create_autocmd("OptionSet", {
		group = group,
		pattern = { "buflisted", "readonly", "modifiable" },
		callback = function()
			dirty = true
			refresh()
		end,
	})
	api.nvim_create_autocmd("ColorScheme", {
		group = group,
		callback = function()
			vim.schedule(function()
				colors()
				refresh()
			end)
		end,
	})
end

return M
