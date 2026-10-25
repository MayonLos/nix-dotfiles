-- A single quiet row: project, branch, document pills, and the search shortcut.
local M = {}
local function esc(s)
	return s:gsub("%%", "%%%%")
end
local function button(id, value, hl)
	return "%#" .. hl .. "#%" .. id .. "@v:lua.MayonToolbarClick@" .. value .. "%X"
end
function M.click(id, _, mouse)
	vim.schedule(function()
		if id >= 100000 then
			local buf = id - 100000
			if mouse == "m" then
				require("snacks").bufdelete({ buf = buf })
			else
				require("mayon.ui.tabline").select(buf)
			end
		elseif id == 1 then
			require("snacks").picker.projects()
		elseif id == 2 then
			require("snacks").picker.git_branches()
		elseif id == 4 then
			require("snacks").picker.buffers()
		end
	end)
end
local icon_groups = {}
local function highlights()
	local p = require("mayon.generated").palette
	vim.api.nvim_set_hl(0, "MayonTabPill", { fg = p.brightFg, bg = p.selection, bold = true })
	vim.api.nvim_set_hl(0, "MayonTabRound", { fg = p.selection, bg = p.deep })
	vim.api.nvim_set_hl(0, "MayonTabModified", { fg = p.orange, bg = p.selection })
	vim.api.nvim_set_hl(0, "MayonTabModifiedInactive", { fg = p.orange, bg = p.deep })
	vim.api.nvim_set_hl(0, "MayonTabError", { fg = p.red, bg = p.selection })
	vim.api.nvim_set_hl(0, "MayonTabErrorInactive", { fg = p.red, bg = p.deep })
	vim.api.nvim_set_hl(0, "MayonTabReadonly", { fg = p.muted, bg = p.selection })
	vim.api.nvim_set_hl(0, "MayonTabReadonlyInactive", { fg = p.dim, bg = p.deep })
	vim.api.nvim_set_hl(0, "MayonTopProject", { fg = p.brightFg, bg = p.deep, bold = true })
	vim.api.nvim_set_hl(0, "MayonTopMuted", { fg = p.muted, bg = p.deep })
	icon_groups = {}
end
local function icon_group(source, active)
	local key = source .. (active and "Active" or "Inactive")
	if not icon_groups[key] then
		local p = require("mayon.generated").palette
		local hl = vim.api.nvim_get_hl(0, { name = source, link = false })
		vim.api.nvim_set_hl(0, "MayonTop" .. key, { fg = hl.fg or p.fg, bg = active and p.selection or p.deep })
		icon_groups[key] = "MayonTop" .. key
	end
	return icon_groups[key]
end
function M.render()
	local tabs = require("mayon.ui.tabline")
	local fit = require("mayon.ui.text").truncate
	local active = tabs.active_buffer()
	local buffers = tabs.buffers()
	local labels = require("mayon.ui.workspace").buffer_labels(buffers)
	local git = vim.b[active or 0].gitsigns_status_dict or {}
	local name = fit(vim.fs.basename(vim.fn.getcwd()), math.max(4, math.min(24, math.floor(vim.o.columns * 0.18))))
	local branch = fit(
		(git.head and git.head ~= "" and git.head) or vim.g.mayon_branch or "",
		math.max(4, math.min(18, math.floor(vim.o.columns * 0.12)))
	)
	local left = button(1, " " .. esc(name) .. " ", "MayonTopProject")
	local used = vim.fn.strdisplaywidth(name) + 2
	if branch ~= "" and vim.o.columns >= 64 then
		left = left .. button(2, " " .. esc(branch) .. " ", "MayonTopMuted")
		used = used + vim.fn.strdisplaywidth(branch) + 2
	end
	left = left .. "%#MayonTopMuted# │ "
	used = used + 3
	local budget = math.max(1, vim.o.columns - used - 2)
	local entries, active_index = {}, 1
	for index, buf in ipairs(buffers) do
		local icon, hl = require("mayon.ui.icons").get(vim.api.nvim_buf_get_name(buf))
		local selected = buf == active
		if selected then
			active_index = index
		end
		local label = fit(labels[buf], 28)
		local modified = vim.bo[buf].modified
		local has_error = #vim.diagnostic.get(buf, { severity = vim.diagnostic.severity.ERROR }) > 0
		local readonly = not vim.bo[buf].modifiable or vim.bo[buf].readonly
		local dot = ""
		if has_error then
			dot = "%#" .. (selected and "MayonTabError" or "MayonTabErrorInactive") .. "# ●"
		elseif modified then
			dot = "%#" .. (selected and "MayonTabModified" or "MayonTabModifiedInactive") .. "# ●"
		elseif readonly then
			dot = "%#" .. (selected and "MayonTabReadonly" or "MayonTabReadonlyInactive") .. "# ·"
		end
		entries[index] = {
			buf = buf,
			icon = icon,
			icon_hl = hl or "Normal",
			label = label,
			selected = selected,
			dot = dot,
			width = vim.fn.strdisplaywidth(icon) + vim.fn.strdisplaywidth(label) + (dot ~= "" and 2 or 0) + 5,
		}
	end
	local function tab_value(entry, label_width)
		local label = fit(entry.label, label_width)
		local selected = entry.selected
		local core = (selected and "%#MayonTabRound#" or "%#MayonTopMuted# ")
			.. "%#"
			.. icon_group(entry.icon_hl, selected)
			.. "#"
			.. esc(entry.icon)
			.. "%#"
			.. (selected and "MayonTabPill" or "MayonTopMuted")
			.. "# "
			.. esc(label)
			.. entry.dot
			.. (selected and "%#MayonTabRound# " or "  ")
		return "%" .. (100000 + entry.buf) .. "@v:lua.MayonToolbarClick@" .. core .. "%X"
	end
	if #entries == 0 then
		return left .. "%#TabLineFill#%="
	end
	-- Always keep the active buffer visible. Reserve enough room for the exact
	-- hidden count, then spend remaining cells on nearby tabs.
	local first, last = active_index, active_index
	local function visible_width()
		local width = 0
		for index = first, last do
			width = width + entries[index].width
		end
		return width
	end
	local hidden = #entries - 1
	local function more_width(count)
		return count > 0 and (vim.fn.strdisplaywidth(" +" .. count .. " ")) or 0
	end
	local width = visible_width()
	while hidden > 0 do
		local candidate
		if first > 1 then
			candidate = entries[first - 1].width
		elseif last < #entries then
			candidate = entries[last + 1].width
		end
		if not candidate or width + candidate + more_width(hidden - 1) > budget then
			break
		end
		if first > 1 then
			first = first - 1
		else
			last = last + 1
		end
		width = width + candidate
		hidden = #entries - (last - first + 1)
	end
	-- A single very long active name must still fit the row.
	if width + more_width(hidden) > budget and first == last then
		local entry = entries[first]
		local fixed = vim.fn.strdisplaywidth(entry.icon) + (entry.dot ~= "" and 2 or 0) + 5
		entry.width = math.max(1, budget - more_width(hidden))
		entry.label_width = math.max(1, entry.width - fixed)
		width = entry.width
	end
	for index = first, last do
		if entries[index] then
			left = left .. tab_value(entries[index], entries[index].label_width or 28)
		end
	end
	if hidden > 0 then
		left = left .. button(4, " +" .. hidden .. " ", "MayonTopMuted")
	end
	return left .. "%#TabLineFill#%="
end
function M.setup()
	if M.ready then
		return
	end
	M.ready = true
	highlights()
	_G.MayonToolbarClick = M.click
	vim.o.tabline = "%!v:lua.require'mayon.ui.toolbar'.render()"
	local group = vim.api.nvim_create_augroup("MayonTopRow", { clear = true })
	vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = vim.schedule_wrap(highlights) })
	vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter", "BufModifiedSet", "BufDelete", "BufFilePost" }, {
		group = group,
		callback = function()
			require("mayon.ui.tabline").active_buffer()
			vim.cmd.redrawtabline()
		end,
	})
	local function branch()
		vim.system({ "git", "branch", "--show-current" }, { cwd = vim.fn.getcwd(), text = true }, function(result)
			local head = result.code == 0 and vim.trim(result.stdout or "") or ""
			vim.schedule(function()
				vim.g.mayon_branch = head
				vim.cmd.redrawtabline()
			end)
		end)
	end
	vim.api.nvim_create_autocmd({ "DirChanged", "FocusGained" }, { group = group, callback = branch })
	branch()
end
return M
