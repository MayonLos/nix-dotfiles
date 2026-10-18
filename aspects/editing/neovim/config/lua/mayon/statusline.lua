local M = {}

local redraw_pending = false
local requests = {}
local request_order = {}
local setup_done = false

local mode_names = {
	n = "NORMAL",
	niI = "NORMAL",
	niR = "NORMAL",
	niV = "NORMAL",
	no = "O-PENDING",
	nov = "O-PENDING",
	noV = "O-PENDING",
	i = "INSERT",
	ic = "INSERT",
	ix = "INSERT",
	v = "VISUAL",
	V = "V-LINE",
	["\22"] = "V-BLOCK",
	s = "SELECT",
	S = "S-LINE",
	["\19"] = "S-BLOCK",
	R = "REPLACE",
	Rv = "V-REPLACE",
	c = "COMMAND",
	cv = "EX",
	r = "PROMPT",
	rm = "MORE",
	["r?"] = "CONFIRM",
	["!"] = "SHELL",
	t = "TERMINAL",
}

local function schedule_redraw()
	if redraw_pending then
		return
	end
	redraw_pending = true
	vim.schedule(function()
		redraw_pending = false
		pcall(vim.cmd, "redrawstatus")
	end)
end

local function text(value)
	return tostring(value or ""):gsub("[\r\n]", " "):gsub("%%", "%%%%")
end

local function truncate(value, width)
	value = tostring(value or "")
	if width <= 0 then
		return ""
	end
	if vim.fn.strdisplaywidth(value) <= width then
		return value
	end
	local out = ""
	for i = 0, vim.fn.strchars(value) - 1 do
		local char = vim.fn.strcharpart(value, i, 1)
		if vim.fn.strdisplaywidth(out .. char .. "…") > width then
			break
		end
		out = out .. char
	end
	return out .. "…"
end

local function part(value, hl)
	if value == nil or value == "" then
		return nil
	end
	value = tostring(value):gsub("[\r\n]", " ")
	return { value = text(value), display_width = vim.fn.strdisplaywidth(value), hl = hl }
end

local function format(parts)
	local out = {}
	for _, item in ipairs(parts) do
		if item then
			if item.hl then
				out[#out + 1] = "%#" .. item.hl .. "#"
			end
			out[#out + 1] = item.value
			if item.hl then
				out[#out + 1] = "%*"
			end
		end
	end
	return table.concat(out)
end

local function width(parts)
	if parts and parts.value then
		return parts.display_width or vim.fn.strdisplaywidth(parts.value)
	end
	local n = 0
	for _, item in ipairs(parts) do
		if item then
			n = n + (item.display_width or vim.fn.strdisplaywidth(item.value))
		end
	end
	return n
end

local function mode_data()
	local mode = vim.fn.mode(1)
	local color = ({
		i = "String",
		v = "Statement",
		V = "Statement",
		["\22"] = "Statement",
		c = "Constant",
		s = "Statement",
		S = "Statement",
		["\19"] = "Statement",
		R = "DiagnosticError",
		r = "DiagnosticError",
		["!"] = "DiagnosticError",
		t = "String",
	})[mode:sub(1, 1)] or "Function"
	return mode_names[mode] or mode:upper(), color
end

local function icon_for(filename)
	local ok, devicons = pcall(require, "nvim-web-devicons")
	if not ok then
		return nil
	end
	local ext = vim.fn.fnamemodify(filename, ":e")
	if type(devicons.get_icon) == "function" then
		local icon, hl = devicons.get_icon(filename, ext, { default = true })
		return icon, hl
	end
	local icon = devicons.get_icon_color(filename, ext, { default = true })
	return icon, "MayonSLIcon"
end

local function is_special(buf)
	local bt = vim.bo[buf].buftype
	local ft = vim.bo[buf].filetype
	if ft == "codecompanion" then
		return false
	end
	return ({ nofile = true, prompt = true, help = true, quickfix = true, terminal = true })[bt]
		or ft:match("^git")
		or ft == "fugitive"
		or ft == "fzf"
		or ft == "qf"
end

local function diagnostics(buf)
	local counts = {}
	local severity = vim.diagnostic.severity
	for _, sev in ipairs({ severity.ERROR, severity.WARN, severity.INFO, severity.HINT }) do
		counts[sev] = #vim.diagnostic.get(buf, { severity = sev })
	end
	local signs = vim.diagnostic.config().signs
	local labels, groups = {}, { "DiagnosticError", "DiagnosticWarn", "DiagnosticInfo", "DiagnosticHint" }
	for i, sev in ipairs({ severity.ERROR, severity.WARN, severity.INFO, severity.HINT }) do
		local count = counts[sev]
		if count > 0 then
			local icon = type(signs) == "table" and signs.text and signs.text[sev] or ""
			labels[#labels + 1] = part(icon .. count .. " ", groups[i])
		end
	end
	return labels
end

local function breadcrumbs(buf, row, col)
	local ok, api = pcall(require, "mayon.breadcrumbs")
	if ok and type(api.get) == "function" then
		local success, items = pcall(api.get, buf, { row = row, col = col })
		if success and type(items) == "table" then
			return items
		end
	end
	return {}
end

local function render_current(target_width, active_win)
	local win = vim.api.nvim_get_current_win()
	local buf = vim.api.nvim_get_current_buf()
	local width_px = target_width or vim.api.nvim_win_get_width(win)
	local mode, mode_color = mode_data()
	local left = { part(" " .. mode .. " ", "MayonSLMode" .. mode_color), part(" ") }
	local right = {}
	local active = win == active_win
	local base_hl = active and "StatusLine" or "StatusLineNC"

	if vim.bo[buf].filetype == "mayon-file-tree" then
		local root = vim.b[buf].mayon_tree_root or ""
		local label = "Files · " .. vim.fn.fnamemodify(root, ":~:.")
		right = width_px >= 70 and { part(" K path · g? help ", "MayonSLMuted") } or {}
		left[#left + 1] = part(truncate(label, math.max(1, width_px - width(left) - width(right) - 1)), "MayonSLText")
		return "%#" .. base_hl .. "#" .. format(left) .. "%=" .. format(right)
	end
	if is_special(buf) then
		right = { part(string.format("%d:%d ", vim.fn.line("."), vim.fn.virtcol(".")), "MayonSLText") }
		left[#left + 1] = part(
			truncate(" " .. vim.bo[buf].filetype:upper() .. " ", math.max(1, width_px - width(left) - width(right) - 1)),
			"MayonSLText"
		)
		return "%#" .. base_hl .. "#" .. format(left) .. "%=" .. format(right)
	end
	if vim.bo[buf].filetype == "codecompanion" then
		local metadata = (_G.codecompanion_chat_metadata or {})[buf] or {}
		local adapter = metadata.adapter
		local position = {
			part(string.format("%d:%d ", vim.fn.line("."), vim.fn.virtcol(".")), "MayonSLText"),
		}
		local adapter_label = "󰚩 " .. (adapter and adapter.name or "CodeCompanion") .. " "
		left[#left + 1] = part(
			truncate(adapter_label, math.max(1, math.min(26, width_px - width(left) - width(position) - 2))),
			"MayonSLPurple"
		)
		if width_px >= 60 then
			for _, item in ipairs({
				{ "Σ", "tokens" },
				{ "⟳", "cycles" },
				{ "⧉", "context_items" },
				{ "⚒", "tools" },
			}) do
				local count = tonumber(metadata[item[2]]) or 0
				if count > 0 then
					local label = part(" " .. item[1] .. " " .. count .. " ", "MayonSLMuted")
					if width(left) + width(right) + width(label) + width(position) + 2 <= width_px then
						right[#right + 1] = label
					end
				end
			end
		end
		vim.list_extend(right, position)
		return "%#" .. base_hl .. "#" .. format(left) .. "%=" .. format(right)
	end

	local filename = vim.api.nvim_buf_get_name(buf)
	local basename = vim.fn.fnamemodify(filename, ":t")
	if basename == "" then
		basename = "[No Name]"
	end
	local icon, icon_hl = icon_for(filename)
	if icon then
		left[#left + 1] = part(icon .. " ", icon_hl or "MayonSLIcon")
	end
	local filename_index = #left + 1
	left[filename_index] = part(basename, "MayonSLText")
	if vim.bo[buf].modified then
		left[#left + 1] = part(" ●", "MayonSLGreen")
	end
	if not vim.bo[buf].modifiable or vim.bo[buf].readonly then
		left[#left + 1] = part(" 󰌾", "MayonSLOrange")
	end

	local breadcrumbs_list =
		breadcrumbs(buf, vim.api.nvim_win_get_cursor(win)[1] - 1, vim.api.nvim_win_get_cursor(win)[2])
	local crumb_parts = {}
	for i = math.max(1, #breadcrumbs_list - 1), #breadcrumbs_list do
		local item = breadcrumbs_list[i]
		crumb_parts[#crumb_parts + 1] = (item.icon or "") .. truncate(item.name or "", 22)
	end
	local crumbs = #crumb_parts > 0 and (" › " .. table.concat(crumb_parts, " › ")) or ""
	local git = vim.b[buf].gitsigns_status_dict
	local git_parts = {}
	if type(git) == "table" and git.head then
		git_parts[#git_parts + 1] =
			part(" ·  " .. truncate(git.head, math.max(1, math.floor(width_px * 0.12))) .. " ", "MayonSLMuted")
		if (git.added or 0) > 0 then
			git_parts[#git_parts + 1] = part("+" .. git.added .. " ", "MayonSLGitAdd")
		end
		if (git.changed or 0) > 0 then
			git_parts[#git_parts + 1] = part("~" .. git.changed .. " ", "MayonSLGitChange")
		end
		if (git.removed or 0) > 0 then
			git_parts[#git_parts + 1] = part("-" .. git.removed .. " ", "MayonSLGitDelete")
		end
	end
	local clients = vim.lsp.get_clients({ bufnr = buf })
	local names = {}
	for _, client in ipairs(clients) do
		names[#names + 1] = client.name
	end
	table.sort(names)
	local lsp_text = #names > 0
			and (width_px < 120 and ("LSP " .. #names .. " ") or (truncate(
				table.concat(names, ","),
				math.floor(width_px * 0.14)
			) .. " "))
		or ""

	local lsp = package.loaded["mayon.lsp"]
	if lsp and type(lsp.progress_status) == "function" then
		local ok, progress = pcall(lsp.progress_status)
		if ok and type(progress) == "table" and #progress > 0 then
			local task = progress[#progress]
			lsp_text = "⋯ "
				.. truncate((task.name or "LSP") .. " " .. (task.message or ""), math.floor(width_px * 0.22))
				.. " "
		end
	end

	local rec = vim.fn.reg_recording()
	if rec ~= "" then
		right[#right + 1] = part("● @" .. rec .. " ", "MayonSLRed")
	end
	if vim.v.hlsearch == 1 then
		local ok, count = pcall(vim.fn.searchcount, { maxcount = 999, timeout = 20 })
		if ok and count.total and count.total > 0 then
			local label = count.incomplete == 1 and "search … "
				or (count.current .. "/" .. count.total .. (count.incomplete == 2 and "+ " or " "))
			right[#right + 1] = part(label, "MayonSLText")
		end
	end
	if #request_order > 0 then
		local name = requests[request_order[#request_order]] or "CodeCompanion"
		right[#right + 1] = part(
			"⋯ " .. truncate(name, 18) .. (#request_order > 1 and (" ×" .. #request_order) or "") .. " ",
			"MayonSLPurple"
		)
	end
	vim.list_extend(right, diagnostics(buf))
	if #names > 0 then
		local item = part(lsp_text, "MayonSLGreen")
		item.is_lsp = true
		right[#right + 1] = item
	end
	right[#right + 1] = { value = "%P " }
	right[#right].display_width = 4
	right[#right + 1] = part(string.format("%d:%d ", vim.fn.line("."), vim.fn.virtcol(".")), "MayonSLText")

	-- Optional context is dropped in order as the target window narrows.
	local optional = {}
	if width_px >= 120 and crumbs ~= "" then
		optional[#optional + 1] = part(truncate(crumbs, math.floor(width_px * 0.26)), "MayonSLMuted")
	end
	if width_px >= 90 then
		vim.list_extend(optional, git_parts)
	end
	if lsp_text ~= "" then
		for i = #right, 1, -1 do
			if right[i].is_lsp then
				table.remove(right, i)
			end
		end
	end
	if width_px >= 70 and lsp_text ~= "" then
		optional[#optional + 1] = part(" · " .. lsp_text, "MayonSLGreen")
	end
	local fixed_left_width = width(left) - width(left[filename_index])
	local available = math.max(1, width_px - fixed_left_width - width(right) - 2)
	left[filename_index] = part(truncate(basename, math.max(1, available)), "MayonSLText")
	for _, item in ipairs(optional) do
		if width(left) + width(item) + width(right) + 2 <= width_px then
			left[#left + 1] = item
		end
	end
	if width_px >= 100 and vim.bo[buf].filetype ~= "" then
		local detail = vim.bo[buf].filetype
		local encoding = vim.bo[buf].fileencoding
		if encoding ~= "" and encoding ~= "utf-8" then
			detail = detail .. " · " .. encoding
		end
		if vim.bo[buf].fileformat ~= "unix" then
			detail = detail .. " · " .. vim.bo[buf].fileformat
		end
		local item = part(" " .. detail .. " · ", "MayonSLMuted")
		if width(left) + width(right) + width(item) + 2 <= width_px then
			table.insert(right, 1, item)
		end
	end
	return "%#" .. base_hl .. "#" .. format(left) .. "%=" .. format(right)
end

function M.render(win)
	win = win or vim.g.statusline_winid
	if type(win) ~= "number" or not vim.api.nvim_win_is_valid(win) then
		win = vim.api.nvim_get_current_win()
	end
	local active_win = vim.api.nvim_get_current_win()
	local width_px = vim.o.laststatus == 3 and vim.o.columns or vim.api.nvim_win_get_width(win)
	local ok, result = pcall(vim.api.nvim_win_call, win, function()
		return render_current(width_px, active_win)
	end)
	return ok and result or ""
end

local function refresh_highlights()
	local links = {
		MayonSLText = "StatusLine",
		MayonSLMuted = "Comment",
		MayonSLGreen = "String",
		MayonSLPurple = "Statement",
		MayonSLOrange = "Constant",
		MayonSLRed = "DiagnosticError",
		MayonSLGitAdd = "Added",
		MayonSLGitChange = "Changed",
		MayonSLGitDelete = "Removed",
		MayonSLIcon = "StatusLine",
		MayonSLModeFunction = "Function",
		MayonSLModeString = "String",
		MayonSLModeStatement = "Statement",
		MayonSLModeConstant = "Constant",
		MayonSLModeDiagnosticError = "DiagnosticError",
	}
	for name, target in pairs(links) do
		local source = vim.api.nvim_get_hl(0, { name = target, link = false })
		-- Foreground-only groups inherit the target bar's active/inactive surface.
		vim.api.nvim_set_hl(0, name, { fg = source.fg, bold = source.bold, italic = source.italic })
	end
	local hl = vim.api.nvim_get_hl(0, { name = "StatusLine", link = false })
	if hl.bg then
		vim.api.nvim_set_hl(
			0,
			"MayonSLModeFunction",
			{ fg = hl.bg, bg = vim.api.nvim_get_hl(0, { name = "Function", link = false }).fg, bold = true }
		)
	end
	for _, name in ipairs({
		"MayonSLModeString",
		"MayonSLModeStatement",
		"MayonSLModeConstant",
		"MayonSLModeDiagnosticError",
	}) do
		local source = name:gsub("^MayonSLMode", "")
		local color = vim.api.nvim_get_hl(0, { name = source, link = false }).fg
		vim.api.nvim_set_hl(0, name, { fg = hl.bg, bg = color, bold = true })
	end
end

function M.setup()
	vim.o.statusline = "%!v:lua.MayonStatusline()"
	_G.MayonStatusline = M.render
	if setup_done then
		return
	end
	setup_done = true
	refresh_highlights()
	local augroup = vim.api.nvim_create_augroup("MayonStatusline", { clear = true })
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = augroup,
		callback = function()
			vim.schedule(function()
				refresh_highlights()
				schedule_redraw()
			end)
		end,
	})
	vim.api.nvim_create_autocmd({
		"ModeChanged",
		"DiagnosticChanged",
		"BufEnter",
		"BufModifiedSet",
		"LspAttach",
		"LspDetach",
		"RecordingEnter",
		"RecordingLeave",
		"CursorMoved",
		"CursorMovedI",
	}, { group = augroup, callback = schedule_redraw })
	vim.api.nvim_create_autocmd(
		"User",
		{ group = augroup, pattern = { "GitSignsUpdate", "MayonLspProgressChanged" }, callback = schedule_redraw }
	)
	vim.api.nvim_create_autocmd("User", {
		group = augroup,
		pattern = {
			"CodeCompanionRequestStarted",
			"CodeCompanionRequestFinished",
			"CodeCompanionChatOpened",
			"CodeCompanionChatModel",
			"CodeCompanionChatDone",
		},
		callback = function(args)
			if args.match == "CodeCompanionRequestStarted" then
				local data = args.data or {}
				local id = data.id
				if id ~= nil and not requests[id] then
					local adapter = data.adapter
					requests[id] = adapter and (adapter.formatted_name or adapter.name) or "CodeCompanion"
					request_order[#request_order + 1] = id
				end
			elseif args.match == "CodeCompanionRequestFinished" then
				local id = (args.data or {}).id
				if id ~= nil and requests[id] then
					requests[id] = nil
					for i, key in ipairs(request_order) do
						if key == id then
							table.remove(request_order, i)
							break
						end
					end
				end
			end
			schedule_redraw()
		end,
	})
end

return M
