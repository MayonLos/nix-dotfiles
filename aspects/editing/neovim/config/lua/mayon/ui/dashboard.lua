-- Snacks 2.31 dashboard configuration. The Snacks module owns rendering;
-- this module only provides the shared palette and workspace actions.
local M = {}

vim.g.mayon_ui_started_at = vim.g.mayon_ui_started_at or vim.uv.hrtime()

local header = {
	{ "M   M   AAA   Y   Y   OOO   N   N\n", hl = "MayonDashboardBlue" },
	{ "MM MM  A   A   Y Y   O   O  NN  N\n", hl = "MayonDashboardBlue" },
	{ "M M M  AAAAA    Y    O   O  N N N\n", hl = "MayonDashboardMix" },
	{ "M   M  A   A    Y    O   O  N  NN\n", hl = "MayonDashboardCyan" },
	{ "M   M  A   A    Y     OOO   N   N", hl = "MayonDashboardCyan" },
}

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
	return {
		enabled = true,
		width = 56,
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
			{ section = "header", padding = 1 },
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
