local M = {}

local function palette()
	return require("mayon.generated").palette
end

local function apply_highlights()
	local c = palette()
	vim.api.nvim_set_hl(0, "MayonPanelRail", { fg = c.blue, bg = c.deep, bold = true })
	vim.api.nvim_set_hl(0, "MayonPanelFile", { fg = c.brightFg, bg = c.deep, bold = true })
	vim.api.nvim_set_hl(0, "MayonPanelPosition", { fg = c.muted, bg = c.deep })
	vim.api.nvim_set_hl(0, "MayonPanelNormal", { fg = c.fg, bg = c.deep })
	vim.api.nvim_set_hl(0, "MayonPanelSelection", { fg = c.brightFg, bg = c.selection })
	local edge = require("mayon.ui.theme").blend(c.border, c.deep, 0.28)
	vim.api.nvim_set_hl(0, "MayonPanelEdge", { fg = edge, bg = c.deep })
end

local function location(entry)
	local line = tonumber(entry.lnum) or 0
	local col = tonumber(entry.col) or 0
	return line > 0 and ("%d:%d"):format(line, math.max(1, col)) or ""
end

local function filename(entry)
	local name = entry.filename
	if (not name or name == "") and tonumber(entry.bufnr) and entry.bufnr > 0 then
		name = vim.api.nvim_buf_get_name(entry.bufnr)
	end
	if not name or name == "" then
		name = "[no file]"
	end
	return vim.fn.fnamemodify(name, ":~:.")
end

local function get_list(info)
	local opts = { id = info.id, all = true }
	local ok, result
	if info.quickfix == 0 and info.winid and info.winid > 0 then
		ok, result = pcall(vim.fn.getloclist, info.winid, opts)
	else
		ok, result = pcall(vim.fn.getqflist, opts)
	end
	return ok and result or { items = {} }
end

function M.formatQuickfix(info)
	local list = get_list(info)
	local items = list.items or {}
	local width = math.max(
		24,
		(info.winid and vim.api.nvim_win_is_valid(info.winid)) and vim.api.nvim_win_get_width(info.winid)
			or vim.o.columns
	)
	local rows = {}
	local previous = nil
	local text = require("mayon.ui.text")
	for index = info.start_idx, info.end_idx do
		local item = items[index]
		if item then
			local path = filename(item)
			local prefix
			if path == previous then
				prefix = "  "
			else
				local group_count = 1
				for next_index = index + 1, #items do
					if filename(items[next_index]) ~= path then
						break
					end
					group_count = group_count + 1
				end
				prefix = ("%s · %d  "):format(path, group_count)
			end
			previous = path
			local pos = location(item)
			local message = vim.trim((item.text or ""):gsub("\n", " "))
			local prefix_width = math.max(2, width - vim.fn.strwidth(pos) - 4)
			prefix = text.truncate(prefix, prefix_width)
			local available = math.max(1, width - vim.fn.strwidth(prefix) - vim.fn.strwidth(pos) - 1)
			message = text.truncate(message, available, "")
			local left = prefix .. message
			local gap = math.max(1, width - vim.fn.strwidth(left) - vim.fn.strwidth(pos))
			rows[#rows + 1] = left .. string.rep(" ", gap) .. pos
		end
	end
	return rows
end

_G.MayonQuickfixText = M.formatQuickfix

local function active_list(win)
	win = tonumber(win) or tonumber(vim.g.statusline_winid)
	if not win or not vim.api.nvim_win_is_valid(win) then
		win = vim.api.nvim_get_current_win()
	end
	local info = vim.fn.getwininfo(win)[1] or {}
	if info.loclist == 1 then
		local ok, list = pcall(vim.fn.getloclist, win, { all = true })
		return ok and list or { items = {} }, true
	end
	local ok, list = pcall(vim.fn.getqflist, { winid = win, all = true })
	return ok and list or { items = {} }, false
end

local function severity_counts(items)
	local errors, warnings = 0, 0
	for _, item in ipairs(items or {}) do
		local user_data = type(item.user_data) == "table" and item.user_data or nil
		local severity = user_data and user_data.severity
		local kind = tostring(item.type or ""):upper()
		if severity == vim.diagnostic.severity.ERROR or kind == "E" or kind == "1" then
			errors = errors + 1
		elseif severity == vim.diagnostic.severity.WARN or kind == "W" or kind == "2" then
			warnings = warnings + 1
		end
	end
	return errors, warnings
end

function M.quickfixTitle(win)
	local list, is_loclist = active_list(win)
	local items = list.items or {}
	local errors, warnings = severity_counts(items)
	local total = list.size or #items
	local title = list.title and list.title ~= "" and (" · " .. require("mayon.ui.text").escape(list.title)) or ""
	local name = is_loclist and "位置列表" or "快速修复"
	return ("%%#MayonPanelTitle#%s%s%%=%%#DiagnosticError#●%d %%#DiagnosticWarn#▲%d %%#MayonPanelPosition#%d 项"):format(
		name,
		title,
		errors,
		warnings,
		total
	)
end
_G.MayonQuickfixTitle = M.quickfixTitle

function M.rail(win, line)
	win = tonumber(win) or tonumber(vim.g.statusline_winid)
	if not win or not vim.api.nvim_win_is_valid(win) then
		win = vim.api.nvim_get_current_win()
	end
	local row = tonumber(line) or tonumber(vim.v.lnum) or 0
	local cursor = vim.api.nvim_win_get_cursor(win)[1]
	if row == cursor then
		return "%#MayonPanelRail#▎%*"
	end
	return " "
end
_G.MayonPanelRail = M.rail

function M.setupQuickfix()
	apply_highlights()
	vim.o.quickfixtextfunc = "v:lua.MayonQuickfixText"
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("MayonDiagnosticPanelPalette", { clear = true }),
		callback = apply_highlights,
	})
	vim.api.nvim_create_autocmd("FileType", {
		group = vim.api.nvim_create_augroup("MayonQuickfixPanel", { clear = true }),
		pattern = "qf",
		callback = function(event)
			local win = vim.api.nvim_get_current_win()
			vim.wo[win].winhighlight =
				"Normal:MayonPanelNormal,NormalNC:MayonPanelNormal,CursorLine:MayonPanelSelection,WinBar:MayonPanelTitle"
			vim.wo[win].winbar = "%!v:lua.MayonQuickfixTitle()"
			vim.wo[win].statuscolumn = "%!v:lua.MayonPanelRail()"
			vim.wo[win].signcolumn = "no"
			vim.wo[win].number = true
			vim.wo[win].numberwidth = 1
			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(event.buf) and vim.api.nvim_win_is_valid(win) then
					vim.api.nvim_win_call(win, function()
						pcall(vim.fn.matchadd, "MayonPanelPosition", [[\v\d+:\d+$]], 10)
						pcall(vim.fn.matchadd, "MayonPanelFile", [[\v^\S.*\ze\s{2}]], 10)
					end)
				end
			end)
		end,
	})
end

local function diagnostic_totals()
	local errors, warnings = 0, 0
	for _, diagnostic in ipairs(vim.diagnostic.get()) do
		if diagnostic.severity == vim.diagnostic.severity.ERROR then
			errors = errors + 1
		elseif diagnostic.severity == vim.diagnostic.severity.WARN then
			warnings = warnings + 1
		end
	end
	return errors, warnings
end

function M.troubleTitle()
	local errors, warnings = diagnostic_totals()
	return ("%%#MayonPanelTitle#诊断 · 当前项目%%=%%#DiagnosticError#●%d %%#DiagnosticWarn#▲%d"):format(
		errors,
		warnings
	)
end
_G.MayonTroubleTitle = M.troubleTitle

function M.troubleOptions()
	local groups = {
		{ "directory" },
		{ "filename", format = "{hl:MayonPanelFile}{basename}{hl} {count}" },
	}
	return {
		focus = true,
		formatters = {
			aligned = function(ctx)
				local width = vim.o.columns
				for _, win in ipairs(vim.api.nvim_list_wins()) do
					if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "trouble" then
						width = vim.api.nvim_win_get_width(win)
						break
					end
				end
				local pos = ("%d:%d"):format(ctx.item.pos[1], ctx.item.pos[2] + 1)
				local available = math.max(8, width - ctx.node:depth() * 2 - 5)
				local message = vim.trim((ctx.item.message or ctx.item.text or ""):gsub("\n", " "))
				message = require("mayon.ui.text").truncate(message, math.max(1, available - #pos - 1))
				return {
					{ text = message, hl = "MayonPanelFile" },
					{
						text = string.rep(" ", math.max(1, available - vim.fn.strdisplaywidth(message) - #pos)) .. pos,
						hl = "MayonPanelPosition",
					},
				}
			end,
		},
		win = {
			position = "bottom",
			size = 12,
			border = "none",
			wo = {
				winhighlight = "Normal:MayonPanelNormal,NormalNC:MayonPanelNormal,CursorLine:MayonPanelSelection,WinBar:MayonPanelTitle",
				winbar = "%!v:lua.MayonTroubleTitle()",
				statuscolumn = "%!v:lua.MayonPanelRail()",
				signcolumn = "no",
				number = true,
				numberwidth = 1,
			},
		},
		icons = {
			indent = { top = "  ", middle = "  ", last = "  ", fold_open = "▾ ", fold_closed = "▸ ", ws = "  " },
		},
		indent_guides = false,
		preview = { type = "main", scratch = false },
		modes = {
			diagnostics = {
				groups = groups,
				sort = { "filename", "pos", "severity", "message" },
				format = "{severity_icon} {aligned}",
			},
			qflist = {
				groups = { { "filename", format = "{hl:MayonPanelFile}{filename}{hl} {count}" } },
				sort = { "filename", "pos", "severity", "message" },
				format = "{severity_icon|item.type:DiagnosticSignWarn} {aligned}",
			},
			loclist = {
				groups = { { "filename", format = "{hl:MayonPanelFile}{filename}{hl} {count}" } },
				sort = { "filename", "pos", "severity", "message" },
				format = "{severity_icon|item.type:DiagnosticSignWarn} {aligned}",
			},
		},
	}
end

function M.setupTrouble()
	apply_highlights()
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("MayonDiagnosticPanelPalette", { clear = false }),
		callback = apply_highlights,
	})
	M.setupQuickfix()
	return require("trouble").setup(M.troubleOptions())
end

return M
