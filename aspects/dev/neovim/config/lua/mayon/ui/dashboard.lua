-- A centered workspace block. Snacks owns history, navigation and actions;
-- fixed icon/key slots and a bounded selection rail keep every row aligned.
local M = {}
local content_width = 60
local selection_ns = vim.api.nvim_create_namespace("MayonDashboardSelection")
local active_dashboard
local function highlights()
	local p = require("mayon.generated").palette
	for name, spec in pairs({
		MayonDashboardNormal = { fg = p.brightFg, bg = p.bg },
		MayonDashboardBright = { fg = p.brightFg, bg = p.bg },
		MayonDashboardMuted = { fg = p.muted, bg = p.bg },
		MayonDashboardBlue = { fg = p.blue, bg = p.bg },
		MayonDashboardKey = { fg = p.muted, bg = p.bg },
		MayonDashboardTitle = { fg = p.fg, bg = p.bg, bold = true },
		MayonDashboardRail = { fg = p.blue, bg = p.selection },
		MayonDashboardSelection = { fg = p.brightFg, bg = p.selection },
		SnacksDashboardNormal = { fg = p.brightFg, bg = p.bg },
		SnacksDashboardTitle = { fg = p.muted, bg = p.bg },
		SnacksDashboardDesc = { fg = p.brightFg, bg = p.bg },
		SnacksDashboardKey = { fg = p.blue, bg = p.bg },
		SnacksDashboardIcon = { fg = p.blue, bg = p.bg },
		SnacksDashboardEndOfBuffer = { fg = p.bg, bg = p.bg },
	}) do
		vim.api.nvim_set_hl(0, name, spec)
	end
end
local function relative_file(file)
	local relative = vim.fs.relpath(vim.fn.getcwd(), file)
	if relative then
		return relative
	end
	local root = vim.fs.root(vim.fs.dirname(file), { ".git", "flake.nix", "pyproject.toml", "package.json" })
	return root and (vim.fs.basename(root) .. "/" .. vim.fs.relpath(root, file)) or vim.fn.fnamemodify(file, ":~")
end

local function dashboard_file(item, ctx)
	local path = item.icon == "directory" and vim.fn.fnamemodify(item.file, ":~:.") or relative_file(item.file)
	return { require("mayon.ui.text").truncate(path, ctx.width or content_width - 9), hl = "MayonDashboardMuted" }
end

local function dashboard_icon(item)
	local icon, hl = item.icon, "MayonDashboardBlue"
	if icon == "directory" then
		icon = "󰉋"
	elseif item.file then
		icon, hl = require("mayon.ui.icons").get(item.file)
	end
	icon = vim.trim(icon or "")
	return { icon, hl = hl, width = 2 }
end

local function selection(d)
	if not d or not d.win or not vim.api.nvim_win_is_valid(d.win) or vim.api.nvim_win_get_buf(d.win) ~= d.buf then
		return
	end
	vim.api.nvim_buf_clear_namespace(d.buf, selection_ns, 0, -1)
	local row = vim.api.nvim_win_get_cursor(d.win)[1]
	for _, item in ipairs(d.items) do
		if item.action and item._ and item._.row == row then
			local line = vim.api.nvim_buf_get_lines(d.buf, row - 1, row, false)[1] or ""
			local col = math.max(0, math.floor(d.col))
			vim.api.nvim_buf_set_extmark(d.buf, selection_ns, row - 1, col, {
				end_col = #line,
				hl_group = "MayonDashboardSelection",
				priority = 10000,
			})
			vim.api.nvim_buf_set_extmark(d.buf, selection_ns, row - 1, col, {
				virt_text = { { "▎", "MayonDashboardRail" } },
				virt_text_pos = "overlay",
				priority = 10001,
			})
			break
		end
	end
end

-- Discover ancestors/history after the first frame, retaining the startup
-- latency guard while letting Snacks own the actual project data and actions.
local project_cache = setmetatable({}, { __mode = "k" })
local project_pending = setmetatable({}, { __mode = "k" })
local function projects(dashboard, limit)
	if not project_cache[dashboard] and not project_pending[dashboard] then
		project_pending[dashboard] = true
		vim.schedule(function()
			project_cache[dashboard] = Snacks.dashboard.sections.projects({ limit = 4, pick = false, session = false })
			project_pending[dashboard] = nil
			if
				dashboard.win
				and vim.api.nvim_win_is_valid(dashboard.win)
				and vim.api.nvim_win_get_buf(dashboard.win) == dashboard.buf
			then
				dashboard:update()
			end
		end)
	end
	return vim.list_slice(project_cache[dashboard] or {}, 1, limit)
end

local actions = {
	{ icon = "󰉋", key = "f", desc = "Open", action = ":lua Snacks.picker.files()" },
	{ icon = "󰍉", key = "g", desc = "Search", action = ":lua Snacks.picker.grep()" },
	{ icon = "󰎔", key = "n", desc = "New", action = ":ene | startinsert" },
	{ icon = "󰒓", key = "c", desc = "Config", action = ":lua Snacks.picker.files({cwd = vim.env.NVIM_CONFIG_DIR})" },
	{ icon = "󰗼", key = "q", desc = "Quit", action = ":qa" },
}
local hidden_actions = {
	{ key = "r", action = ":lua Snacks.picker.recent()" },
	{ key = "p", action = ":lua Snacks.picker.projects()" },
	{ key = "a", action = ":ClaudeCode" },
	{
		key = "s",
		action = function()
			local sessions = require("mayon.features.sessions")
			sessions.setup()
			sessions.last()
		end,
	},
}
local function heading(text)
	return { text = { { "  " .. text, hl = "MayonDashboardMuted" } } }
end
function M.config()
	highlights()
	local group = vim.api.nvim_create_augroup("MayonDashboard", { clear = true })
	vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = highlights })
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "SnacksDashboardUpdatePre",
		callback = function()
			local d = active_dashboard
			if
				not d
				or not d.win
				or not vim.api.nvim_win_is_valid(d.win)
				or vim.api.nvim_win_get_buf(d.win) ~= d.buf
			then
				return
			end
			local row = vim.api.nvim_win_get_cursor(d.win)[1]
			for _, item in ipairs(d.items or {}) do
				if item.action and item._ and item._.row == row then
					d._mayon_selection = item.file or item.key
					break
				end
			end
		end,
	})
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "SnacksDashboardUpdatePost",
		callback = function()
			local d = active_dashboard
			if
				not d
				or not d.win
				or not vim.api.nvim_win_is_valid(d.win)
				or vim.api.nvim_win_get_buf(d.win) ~= d.buf
			then
				return
			end
			vim.o.laststatus = 3
			require("mayon.ui.tabline").refresh()
			vim.wo[d.win].winbar = ""
			vim.wo[d.win].spell = false
			vim.wo[d.win].cursorline = false
			vim.wo[d.win].winhighlight =
				"Normal:SnacksDashboardNormal,NormalNC:SnacksDashboardNormal,EndOfBuffer:SnacksDashboardEndOfBuffer"
			if d._mayon_selection then
				for _, item in ipairs(d.items) do
					if item._ and (item.file or item.key) == d._mayon_selection then
						vim.api.nvim_win_set_cursor(d.win, { item._.row, math.floor(d.col) + 5 })
						break
					end
				end
			end
			selection(d)
		end,
	})
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = group,
		callback = function(ev)
			local d = active_dashboard
			if d and d.buf == ev.buf then
				vim.schedule(function()
					selection(d)
				end)
			end
		end,
	})
	return {
		enabled = true,
		width = content_width,
		formats = {
			file = dashboard_file,
			icon = dashboard_icon,
			key = { " %s ", hl = "MayonDashboardKey" },
			desc = { "%s", hl = "MayonDashboardBright" },
		},
		preset = { keys = { { key = "q", desc = "Quit", action = ":qa" } } },
		sections = {
			function(d)
				active_dashboard = d
				content_width = math.max(24, math.min(60, d._size.width - 4))
				d.opts.width = content_width
				d.opts.col = math.max(0, math.floor((d._size.width - content_width) / 2))
				local limit = d._size.height < 32 and 2 or 3
				local rows = {
					{
						text = {
							{ "  Neovim", hl = "MayonDashboardTitle" },
							{
								"  ·  " .. require("mayon.ui.text").truncate(
									vim.fs.basename(vim.fn.getcwd()),
									content_width - 16
								),
								hl = "MayonDashboardMuted",
							},
						},
					},
					{ text = "" },
					heading("Recent Projects"),
				}
				local items = projects(d, limit)
				for _, item in ipairs(items) do
					rows[#rows + 1] = vim.tbl_extend("force", item, { indent = 2 })
				end
				if #items == 0 then
					rows[#rows + 1] = { text = { { "     No recent projects", hl = "MayonDashboardMuted" } } }
				end
				rows[#rows + 1] = { text = "" }
				rows[#rows + 1] = heading("Recent Files")
				local recent = Snacks.dashboard.sections.recent_files({ limit = limit })()
				for _, item in ipairs(recent) do
					rows[#rows + 1] = vim.tbl_extend("force", item, { indent = 2 })
				end
				if #recent == 0 then
					rows[#rows + 1] = { text = { { "     No recent files", hl = "MayonDashboardMuted" } } }
				end
				rows[#rows + 1] = { text = "" }
				rows[#rows + 1] = heading("Actions")
				for _, action in ipairs(actions) do
					rows[#rows + 1] = vim.tbl_extend("force", action, { indent = 2 })
				end
				for _, action in ipairs(hidden_actions) do
					rows[#rows + 1] = vim.tbl_extend("force", action, { hidden = true })
				end
				return rows
			end,
		},
	}
end
return M
