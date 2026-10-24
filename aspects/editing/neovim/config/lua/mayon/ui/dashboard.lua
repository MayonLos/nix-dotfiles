-- Snacks 2.31 dashboard configuration. The Snacks module owns rendering;
-- this module only provides the shared palette and workspace actions.
local M = {}

vim.g.mayon_ui_started_at = vim.g.mayon_ui_started_at or vim.uv.hrtime()

local glyphs = {
	{
		"███╗   ███╗",
		"████╗ ████║",
		"██╔████╔██║",
		"██║╚██╔╝██║",
		"██║ ╚═╝ ██║",
		"╚═╝     ╚═╝",
	},
	{
		" █████╗ ",
		"██╔══██╗",
		"███████║",
		"██╔══██║",
		"██║  ██║",
		"╚═╝  ╚═╝",
	},
	{
		"██╗   ██╗",
		"╚██╗ ██╔╝",
		" ╚████╔╝ ",
		"  ╚██╔╝  ",
		"   ██║   ",
		"   ╚═╝   ",
	},
	{
		" ██████╗ ",
		"██╔═══██╗",
		"██║   ██║",
		"██║   ██║",
		"╚██████╔╝",
		" ╚═════╝ ",
	},
	{
		"██╗   ██╗",
		"███╗  ██║",
		"████╗ ██║",
		"██╔██╗██║",
		"██║╚████║",
		"╚═╝ ╚═══╝",
	},
}
local header_rows = {}
for row = 1, 6 do
	local letters = {}
	for _, glyph in ipairs(glyphs) do
		local width = 0
		for _, line in ipairs(glyph) do
			width = math.max(width, vim.fn.strdisplaywidth(line))
		end
		local text = glyph[row]
		letters[#letters + 1] = text .. string.rep(" ", width - vim.fn.strdisplaywidth(text))
	end
	header_rows[row] = table.concat(letters, "  ")
end

local function dashboard_palette()
	local palette = require("mayon.generated").palette
	local function channel(hex, offset)
		return tonumber(hex:sub(offset, offset + 1), 16)
	end
	local function mix(from, to, amount)
		local result = "#"
		for offset = 2, 6, 2 do
			local value = math.floor(channel(from, offset) * (1 - amount) + channel(to, offset) * amount + 0.5)
			result = result .. string.format("%02x", value)
		end
		return result
	end
	for index = 1, #header_rows do
		vim.api.nvim_set_hl(0, "MayonDashboardGradient" .. index, {
			fg = mix(palette.blue, palette.cyan, (index - 1) / (#header_rows - 1)),
			bold = true,
		})
	end
end

local function install_dashboard_palette()
	dashboard_palette()
	local group = vim.api.nvim_create_augroup("MayonDashboardPalette", { clear = true })
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		callback = dashboard_palette,
	})
end

local header = {}
for index, row in ipairs(header_rows) do
	header[index] = { row .. (index < #header_rows and "\n" or ""), hl = "MayonDashboardGradient" .. index }
end

local function relative_parent(file)
	local root = vim.fs.root(file, { ".git", "pyproject.toml", "pyrightconfig.json", "package.json" })
	local parent = vim.fn.fnamemodify(file, ":h")
	if root then
		parent = vim.fs.relpath(root, parent) or parent
	else
		parent = vim.fn.fnamemodify(parent, ":~")
	end
	return parent == "" and "." or parent
end

local function trim_left(text, width)
	if width <= 0 then
		return ""
	end
	if vim.fn.strdisplaywidth(text) <= width then
		return text
	end
	local result = ""
	local used = 1 -- reserve one cell for the leading ellipsis
	local chars = vim.fn.strchars(text)
	for index = chars - 1, 0, -1 do
		local char = vim.fn.strcharpart(text, index, 1)
		local char_width = vim.fn.strdisplaywidth(char)
		if used + char_width > width then
			break
		end
		result = char .. result
		used = used + char_width
	end
	return "…" .. result
end

local function dashboard_file(item, ctx)
	local filename = vim.fn.fnamemodify(item.file, ":t")
	local parent = relative_parent(item.file)
	local available = math.max(0, (ctx.width or 56) - vim.fn.strdisplaywidth(filename) - 3)
	parent = trim_left(parent, available)
	return {
		{ filename, hl = "MayonDashboardCyan" },
		{ "  " .. parent, hl = "MayonDashboardMuted" },
	}
end

local function feed(lhs)
	local keys = vim.api.nvim_replace_termcodes(lhs, true, false, true)
	vim.api.nvim_feedkeys(keys, "m", false)
end

local function startup_footer()
	local elapsed = vim.g.mayon_startup_ms
	if type(elapsed) ~= "number" then
		-- The main bootstrap can set mayon_startup_ms before loading config;
		-- fallback measures from UI module initialization for direct -u use.
		local started = vim.g.mayon_ui_started_at
		if type(started) == "number" then
			elapsed = (vim.uv.hrtime() - started) / 1e6
		else
			elapsed = 0
		end
	end
	return {
		align = "center",
		text = {
			{ "MAYON", hl = "MayonDashboardCyan" },
			{ "  ·  ", hl = "MayonDashboardMuted" },
			{ string.format("配置 %.1f ms", elapsed), hl = "MayonDashboardBlue" },
		},
	}
end

function M.config()
	install_dashboard_palette()
	return {
		enabled = true,
		width = 56,
		formats = { file = dashboard_file },
		preset = {
			header = header,
			keys = {
				{ icon = " ", key = "n", desc = "新建文件", action = ":ene | startinsert" },
				{ icon = " ", key = "f", desc = "查找文件", action = ":lua Snacks.picker.files()" },
				{ icon = " ", key = "r", desc = "最近文件", action = ":lua Snacks.picker.recent()" },
				{ icon = " ", key = "g", desc = "全文搜索", action = ":lua Snacks.picker.grep()" },
				{ icon = "󰉋 ", key = "p", desc = "项目列表", action = ":lua Snacks.picker.projects()" },
				{
					icon = " ",
					key = "s",
					desc = "恢复最近会话",
					action = function()
						feed((vim.g.mapleader or "\\") .. "pl")
					end,
				},
				{
					icon = " ",
					key = "c",
					desc = "打开配置",
					action = ":lua Snacks.picker.files({cwd = vim.env.NVIM_CONFIG_DIR})",
				},
				{ icon = " ", key = "q", desc = "退出", action = ":qa" },
			},
		},
		sections = {
			{ section = "header", align = "center", padding = 1 },
			{ section = "keys", gap = 0, padding = 1 },
			{ section = "recent_files", title = "最近文件", icon = " ", limit = 4, indent = 2 },
			{
				section = "projects",
				title = "项目",
				icon = "󰉋 ",
				limit = 4,
				pick = false,
				session = false,
				indent = 2,
			},
			startup_footer,
		},
	}
end

return M
