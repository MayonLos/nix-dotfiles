-- Snacks owns the dashboard buffer and recent/project actions. This module
-- keeps its content as a small, palette-driven TUI rather than a large logo.
local M = {}

vim.g.mayon_ui_started_at = vim.g.mayon_ui_started_at or vim.uv.hrtime()

local content_width = 72
local menu_width = 34
local menu_gap = 4
local menu_rows = {}
local active_dashboard
local render_context
local menu_ns = vim.api.nvim_create_namespace("MayonDashboardMenu")

local function palette()
	return require("mayon.generated").palette
end

local function dashboard_palette()
	local p = palette()
	local groups = {
		MayonDashboardNormal = { fg = p.fg, bg = p.bg },
		MayonDashboardMuted = { fg = p.muted, bg = p.bg },
		MayonDashboardBright = { fg = p.brightFg, bg = p.bg },
		MayonDashboardBlue = { fg = p.blue, bg = p.bg, bold = true },
		MayonDashboardGreen = { fg = p.green, bg = p.bg },
		MayonDashboardKey = { fg = p.muted, bg = p.surface },
		MayonDashboardKeyActive = { fg = p.blue, bg = p.selection, bold = true },
		MayonDashboardSelection = { fg = p.brightFg, bg = p.selection },
		MayonDashboardSelectedIcon = { fg = p.blue, bg = p.selection },
		MayonDashboardRule = { fg = require("mayon.ui.theme").blend(p.border, p.deep, 0.28), bg = p.bg },
	}
	for name, spec in pairs(groups) do
		vim.api.nvim_set_hl(0, name, spec)
	end
	-- Snacks' linked default leaves some terminal backgrounds inherited. Pin all
	-- dashboard window text groups to the same palette background.
	vim.api.nvim_set_hl(0, "SnacksDashboardNormal", { fg = p.fg, bg = p.bg })
	vim.api.nvim_set_hl(0, "SnacksDashboardEndOfBuffer", { fg = p.bg, bg = p.bg })
end

local function install_dashboard_palette()
	dashboard_palette()
	local group = vim.api.nvim_create_augroup("MayonDashboardPalette", { clear = true })
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		callback = dashboard_palette,
	})
end

local function display_width(value)
	return vim.api.nvim_strwidth(value)
end

local function fit_left(value, width)
	if width <= 0 then
		return ""
	end
	if display_width(value) <= width then
		return value .. string.rep(" ", width - display_width(value))
	end
	local chars, used, result = vim.fn.strchars(value), 1, ""
	for index = 0, chars - 1 do
		local char = vim.fn.strcharpart(value, index, 1)
		local char_width = display_width(char)
		if used + char_width > width then
			break
		end
		result = result .. char
		used = used + char_width
	end
	return result .. "…" .. string.rep(" ", math.max(0, width - used))
end

local function fit_right(value, width)
	if display_width(value) > width then
		local chars, result, used = vim.fn.strchars(value), "", 1
		for index = chars - 1, 0, -1 do
			local char = vim.fn.strcharpart(value, index, 1)
			local char_width = display_width(char)
			if used + char_width > width then
				break
			end
			result = char .. result
			used = used + char_width
		end
		value = "…" .. result
	end
	return string.rep(" ", math.max(0, width - display_width(value))) .. value
end

local function current_root()
	local cwd = vim.fn.getcwd()
	return vim.fs.root(cwd, { ".git", "flake.nix", "pyproject.toml", "package.json" }) or cwd
end

local function git_branch(root)
	local git_path = root .. "/.git"
	local stat = vim.uv.fs_stat(git_path)
	if not stat then
		return ""
	end
	if stat.type == "file" then
		local marker = vim.fn.readfile(git_path, "", 1)[1] or ""
		local relative = marker:match("^gitdir:%s*(.+)$")
		if not relative then
			return ""
		end
		git_path = vim.fs.normalize(relative:sub(1, 1) == "/" and relative or (root .. "/" .. relative))
	else
		git_path = git_path
	end
	if vim.fn.filereadable(git_path .. "/HEAD") == 0 then
		return ""
	end
	local head = vim.fn.readfile(git_path .. "/HEAD", "", 1)[1] or ""
	return head:match("^ref:%s+refs/heads/(.+)$") or ""
end

local function project_context()
	if render_context then
		return unpack(render_context)
	end
	local root = current_root()
	local home = (vim.uv.os_get_passwd() or {}).homedir or vim.env.HOME or ""
	local shown = root
	if home ~= "" and root:sub(1, #home) == home then
		shown = "~" .. root:sub(#home + 1)
	end
	local branch = git_branch(root)
	return root, shown, branch
end

local function title_line()
	local _, root, branch = project_context()
	local context = root .. (branch ~= "" and (" · " .. branch) or "")
	local available = content_width - display_width("mayon.nvim") - 2
	context = fit_right(context, available)
	local gap = content_width - display_width("mayon.nvim") - display_width(context)
	return {
		{ "mayon", hl = "MayonDashboardBright" },
		{ ".", hl = "MayonDashboardBlue" },
		{ "nvim", hl = "MayonDashboardBright" },
		{ string.rep(" ", math.max(1, gap)), hl = "MayonDashboardNormal" },
		{ context, hl = "MayonDashboardMuted" },
	}
end

local function title_section()
	return { text = title_line(), padding = { 0, 0 } }
end

local function rule_section()
	return {
		text = {
			{ string.rep("━", math.min(48, content_width)), hl = "MayonDashboardBlue" },
			{ string.rep("─", math.max(0, content_width - 48)), hl = "MayonDashboardRule" },
		},
		padding = { 1, 0 },
	}
end

local actions = {
	{ key = "f", icon = "⌕", desc = "查找文件", action = ":lua Snacks.picker.files()" },
	{ key = "g", icon = "⌗", desc = "全文搜索", action = ":lua Snacks.picker.grep()" },
	{ key = "r", icon = "◷", desc = "最近文件", action = ":lua Snacks.picker.recent()" },
	{
		key = "s",
		icon = "↶",
		desc = "恢复会话",
		action = function()
			local sessions = require("mayon.features.sessions")
			sessions.setup()
			sessions.last()
		end,
	},
	{ key = "p", icon = "▣", desc = "项目列表", action = ":lua Snacks.picker.projects()" },
	{ key = "a", icon = "✳", desc = "Claude Code", action = ":ClaudeCode" },
	{ key = "n", icon = "+", desc = "新建文件", action = ":ene | startinsert" },
	{ key = "c", icon = "⚙", desc = "配置", action = ":lua Snacks.picker.files({cwd = vim.env.NVIM_CONFIG_DIR})" },
}

local function menu_cell(action)
	local prefix = " " .. fit_left(action.icon, 2) .. " "
	return {
		{ prefix, hl = "MayonDashboardBlue" },
		{ fit_left(action.desc, menu_width - 3 - display_width(prefix)), hl = "MayonDashboardBright" },
		{ " " .. action.key .. " ", hl = "MayonDashboardKey" },
	}
end

local function menu_section()
	local result = {}
	for index = 1, #actions, 2 do
		local left, right = actions[index], actions[index + 1]
		local spans = menu_cell(left)
		spans[#spans + 1] = { string.rep(" ", menu_gap) }
		vim.list_extend(spans, menu_cell(right))
		local item = { text = spans, key = left.key, action = left.action }
		item.render = function(_, pos)
			local left_text, right_text = "", ""
			for _, span in ipairs(menu_cell(left)) do
				left_text = left_text .. span[1]
			end
			for _, span in ipairs(menu_cell(right)) do
				right_text = right_text .. span[1]
			end
			menu_rows[pos[1] - 1] = {
				base_col = pos[2] + 1,
				left = left,
				right = right,
				left_bytes = #left_text,
				right_bytes = #right_text,
			}
		end
		result[#result + 1] = item
		result[#result + 1] = { hidden = true, key = right.key, action = right.action }
	end
	return result
end

local function group_heading(label, right)
	local rhs = fit_right(right or "", content_width - display_width(label) - 2)
	local left_width = display_width(label)
	local rhs_width = display_width(rhs)
	local gap = math.max(1, content_width - left_width - rhs_width)
	return {
		text = {
			{ label, hl = "MayonDashboardMuted" },
			{ string.rep(" ", gap), hl = "MayonDashboardNormal" },
			{ rhs, hl = "MayonDashboardMuted" },
		},
		padding = { 0, 1 },
	}
end

local function recent_section()
	local _, shown = project_context()
	local rows = { group_heading("RECENT", shown) }
	local recent = Snacks.dashboard.sections.recent_files({ limit = 4 })()
	for _, item in ipairs(recent) do
		item.indent = 2
		rows[#rows + 1] = item
	end
	return rows
end

local project_rows = setmetatable({}, { __mode = "k" })
local project_pending = setmetatable({}, { __mode = "k" })
local function projects_section(dashboard)
	local rows = { group_heading("PROJECTS") }
	if not project_rows[dashboard] and not project_pending[dashboard] then
		project_pending[dashboard] = true
		-- Recent files and their icons belong to frame one. Project discovery
		-- walks history and ancestors, so let the first dashboard frame render.
		vim.schedule(function()
			project_rows[dashboard] = Snacks.dashboard.sections.projects({ limit = 3, pick = false, session = false })
			project_pending[dashboard] = nil
			if
				dashboard.win
				and dashboard.buf
				and vim.api.nvim_win_is_valid(dashboard.win)
				and vim.api.nvim_win_get_buf(dashboard.win) == dashboard.buf
			then
				dashboard:update()
			end
		end)
	end
	for _, item in ipairs(project_rows[dashboard] or {}) do
		item.indent = 2
		rows[#rows + 1] = item
	end
	return rows
end

local function trim_left(text, width)
	if width <= 0 then
		return ""
	end
	if display_width(text) <= width then
		return text
	end
	local result = ""
	local used = 1
	for index = vim.fn.strchars(text) - 1, 0, -1 do
		local char = vim.fn.strcharpart(text, index, 1)
		local char_width = display_width(char)
		if used + char_width > width then
			break
		end
		result = char .. result
		used = used + char_width
	end
	return "…" .. result
end

local function relative_parent(file)
	local root = vim.fs.root(file, { ".git", "flake.nix", "pyproject.toml", "package.json" })
	local parent = vim.fn.fnamemodify(file, ":h")
	if root then
		parent = vim.fs.relpath(root, parent) or parent
	else
		parent = vim.fn.fnamemodify(parent, ":~")
	end
	return parent == "" and "." or parent
end

local function dashboard_file(item, ctx)
	local filename = vim.fn.fnamemodify(item.file, ":t")
	local width = math.max(0, (ctx.width or content_width) - 2)
	local parent
	if item.icon == "directory" then
		local home = (vim.uv.os_get_passwd() or {}).homedir or vim.env.HOME or ""
		parent = vim.fn.fnamemodify(item.file, ":h")
		if home ~= "" and parent:sub(1, #home) == home then
			parent = "~" .. parent:sub(#home + 1)
		end
	else
		parent = relative_parent(item.file)
	end
	if display_width(parent) > 20 then
		parent = "…/" .. (parent:match("([^/]+/[^/]+)$") or parent:match("([^/]+)$") or parent)
	end
	local parent_width =
		math.max(0, math.min(20, display_width(parent), width - math.min(28, display_width(filename)) - 2))
	local filename_width = math.max(1, width - parent_width - 2)
	filename = fit_left(filename, filename_width)
	parent = trim_left(parent, parent_width)
	local gap = math.max(2, width - display_width(filename) - display_width(parent))
	return {
		{ filename, hl = "MayonDashboardBright" },
		{ string.rep(" ", gap), hl = "MayonDashboardNormal" },
		{ parent, hl = "MayonDashboardMuted" },
	}
end

local function dashboard_icon(item)
	if item.icon == "directory" then
		return { "▸ ", hl = "MayonDashboardBlue", width = 2 }
	end
	-- Missing icons remain blank rather than exposing Snacks' category labels.
	local icon, highlight = require("mayon.ui.icons").get(item.file)
	return { icon, hl = highlight, width = vim.fn.strdisplaywidth(icon) }
end

local function startup_footer()
	local elapsed = vim.g.mayon_startup_ms
	if type(elapsed) ~= "number" then
		local started = vim.g.mayon_ui_started_at
		elapsed = type(started) == "number" and (vim.uv.hrtime() - started) / 1e6 or 0
	end
	local plugin_count = vim.tbl_count(require("mayon.generated").plugin_dependencies)
	local version = vim.version()
	local nvim_version = string.format("nvim %d.%d.%d", version.major, version.minor, version.patch)
	return {
		text = {
			{ "● ", hl = "MayonDashboardGreen" },
			{ tostring(plugin_count) .. " plugins", hl = "MayonDashboardMuted" },
			{ " · ", hl = "MayonDashboardMuted" },
			{ string.format("%.1f ms", elapsed), hl = "MayonDashboardMuted" },
			{ " · " .. nvim_version .. " · ", hl = "MayonDashboardMuted" },
			{ "● ", hl = "MayonDashboardGreen" },
			{ "copilot", hl = "MayonDashboardMuted" },
		},
		align = "center",
		padding = { 1, 0 },
	}
end

local function install_selection()
	local group = vim.api.nvim_create_augroup("MayonDashboardSelection", { clear = true })
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "SnacksDashboardUpdatePost",
		callback = function()
			local dashboard = active_dashboard
			if
				not dashboard
				or not vim.api.nvim_buf_is_valid(dashboard.buf)
				or not vim.api.nvim_win_is_valid(dashboard.win)
				or vim.api.nvim_win_get_buf(dashboard.win) ~= dashboard.buf
			then
				return
			end
			local buf, win = dashboard.buf, dashboard.win
			if vim.bo[buf].filetype ~= "snacks_dashboard" then
				return
			end
			-- Snacks suppresses both bars at startup; retain our dashboard rail.
			vim.o.laststatus = 3
			if vim.api.nvim_get_current_buf() == buf then
				vim.o.showtabline = 0
			end
			vim.wo[win].cursorline = false
			vim.wo[win].winhighlight =
				"Normal:SnacksDashboardNormal,NormalNC:SnacksDashboardNormal,EndOfBuffer:SnacksDashboardEndOfBuffer"
			-- Native Snacks assumes one actionable item per row. Our grid retains
			-- its shortcuts but uses byte-correct cell selection and Enter dispatch.
			pcall(vim.api.nvim_del_augroup_by_name, "snacks_dashboard_cursor")
			local function selection()
				if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(win) then
					return
				end
				vim.api.nvim_buf_clear_namespace(buf, menu_ns, 0, -1)
				local cursor = vim.api.nvim_win_get_cursor(win)
				local row, col = cursor[1] - 1, cursor[2]
				local item = menu_rows[row]
				if not item then
					return
				end
				local right = col >= item.base_col + item.left_bytes + menu_gap
				local start = item.base_col + (right and (item.left_bytes + menu_gap) or 0)
				local action = right and item.right or item.left
				local overlay = {
					{ "▎" .. fit_left(action.icon, 2) .. " ", "MayonDashboardSelectedIcon" },
					{
						fit_left(action.desc, menu_width - 3 - display_width(" " .. fit_left(action.icon, 2) .. " ")),
						"MayonDashboardSelection",
					},
					{ " " .. action.key .. " ", "MayonDashboardKeyActive" },
				}
				vim.api.nvim_buf_set_extmark(buf, menu_ns, row, start, {
					virt_text = overlay,
					virt_text_pos = "overlay",
					priority = 10000,
				})
			end
			local rows = vim.tbl_keys(menu_rows)
			table.sort(rows)
			local function move(horizontal, vertical)
				local cursor = vim.api.nvim_win_get_cursor(win)
				local row = cursor[1] - 1
				local previous = menu_rows[row]
				local side = horizontal
					or (previous and cursor[2] >= previous.base_col + previous.left_bytes + menu_gap and 1 or 0)
				if vertical then
					local targets = {}
					for _, candidate in ipairs(dashboard.items) do
						if candidate.action and candidate._ then
							targets[#targets + 1] = candidate._.row - 1
						end
					end
					table.sort(targets)
					if vertical > 0 then
						for _, target in ipairs(targets) do
							if target > row then
								row = target
								break
							end
						end
					else
						for index = #targets, 1, -1 do
							if targets[index] < row then
								row = targets[index]
								break
							end
						end
					end
				end
				local item = menu_rows[row]
				local col = item and (item.base_col + (side == 1 and (item.left_bytes + menu_gap) or 0)) or cursor[2]
				vim.api.nvim_win_set_cursor(win, { row + 1, col })
				selection()
			end
			for lhs, direction in pairs({ h = 0, l = 1, ["<Left>"] = 0, ["<Right>"] = 1 }) do
				vim.keymap.set("n", lhs, function()
					move(direction)
				end, { buffer = buf, silent = true })
			end
			for lhs, direction in pairs({ j = 1, k = -1, ["<Down>"] = 1, ["<Up>"] = -1 }) do
				vim.keymap.set("n", lhs, function()
					move(nil, direction)
				end, { buffer = buf, silent = true })
			end
			vim.api.nvim_clear_autocmds({ group = group, buffer = buf, event = "CursorMoved" })
			vim.api.nvim_create_autocmd("CursorMoved", { group = group, buffer = buf, callback = selection })
			vim.keymap.set("n", "q", "<cmd>qa<cr>", { buffer = buf, silent = true, nowait = true })
			vim.api.nvim_clear_autocmds({ group = group, buffer = buf, event = { "BufEnter", "BufLeave" } })
			vim.api.nvim_create_autocmd("BufLeave", {
				group = group,
				buffer = buf,
				callback = function()
					if vim.api.nvim_win_is_valid(win) then
						vim.wo[win].cursorline = true
						vim.wo[win].cursorlineopt = "both"
					end
					if vim.o.showtabline == 0 then
						vim.o.showtabline = 2
					end
				end,
			})
			vim.api.nvim_create_autocmd("BufEnter", {
				group = group,
				buffer = buf,
				callback = function()
					vim.o.showtabline, vim.o.laststatus = 0, 3
				end,
			})
			-- Map Enter to the grid cell; non-grid recent/project rows retain their
			-- original Snacks shortcut action through the dashboard instance.
			vim.keymap.set("n", "<cr>", function()
				local cursor = vim.api.nvim_win_get_cursor(win)
				local item = menu_rows[cursor[1] - 1]
				if not item then
					local target = dashboard:find(cursor)
					if target and target.action then
						dashboard:action(target.action)
					end
					return
				end
				local right = cursor[2] >= item.base_col + item.left_bytes + menu_gap
				local action = (right and item.right or item.left).action
				if type(action) == "function" then
					action()
				else
					vim.cmd(action:sub(2))
				end
			end, { buffer = buf, silent = true })
			if rows[1] then
				vim.api.nvim_win_set_cursor(win, { rows[1] + 1, menu_rows[rows[1]].base_col })
			end
			selection()
		end,
	})
end

function M.config()
	install_dashboard_palette()
	install_selection()
	return {
		enabled = true,
		width = content_width,
		row = 6,
		formats = {
			file = dashboard_file,
			icon = dashboard_icon,
			key = { " %s ", hl = "MayonDashboardKey" },
		},
		preset = {
			keys = {
				{ key = "q", desc = "退出", action = ":qa" },
			},
		},
		sections = {
			function(dashboard)
				active_dashboard = dashboard
				render_context = nil
				render_context = { project_context() }
				content_width = math.max(24, math.min(72, dashboard._size.width - 4))
				menu_width = math.floor((content_width - menu_gap) / 2)
				dashboard.opts.width = content_width
				menu_rows = {}
				local result = { title_section(), rule_section() }
				vim.list_extend(result, menu_section())
				local recent, projects = recent_section(), projects_section(dashboard)
				vim.list_extend(result, recent)
				vim.list_extend(result, projects)
				-- Leave the footer near the bottom, independently of history length.
				local height = 2 + 1 + 4 + #recent + #projects + 2
				local footer = startup_footer()
				footer.padding = { 0, math.max(1, dashboard._size.height - 6 - height - 3) }
				result[#result + 1] = footer
				return result
			end,
		},
	}
end

return M
