-- Real optional-plugin setup, dashboard rendering, picker routing and folds.
vim.api.nvim_exec_autocmds("User", { pattern = "MayonVeryLazy" })
require("lz.n").trigger_load({ "codecompanion.nvim", "codediff.nvim", "grug-far.nvim", "trouble.nvim", "yazi.nvim" })
vim.wait(80)
assert(not vim.g.mayon_load_error, vim.g.mayon_load_error)
assert(package.loaded.codecompanion and package.loaded.codediff and package.loaded["vim._core.ui2"])
local cc = require("codecompanion.config").config
assert(cc.interactions.chat.adapter == "deepseek")
assert(cc.extensions.history.enabled)

local snacks = require("snacks")
vim.o.columns, vim.o.lines = 120, 45
local dashboard = snacks.dashboard.open({ win = 0, buf = 0 })
local rendered = vim.api.nvim_buf_get_lines(dashboard.buf, 0, -1, false)
local lines = table.concat(rendered, "\n")
assert(
	lines:find("███╗", 1, true) and lines:find("新建文件", 1, true),
	"dashboard header/keys did not render"
)
assert(lines:find("ms", 1, true), "dashboard lacks its config timing footer")
assert(vim.bo[dashboard.buf].filetype == "snacks_dashboard")
local header_row
local gradient_colors = {}
for index, line in ipairs(rendered) do
	if not header_row and line:find("███╗", 1, true) then
		header_row = index
	end
end
assert(header_row and rendered[header_row]:find("███╗", 1, true), "dashboard MAYON header did not render")
assert(rendered[header_row + 2]:find("╚████╔╝", 1, true), "the third dashboard glyph should be Y")
assert(rendered[header_row + 5]:find("╚═╝", 1, true), "dashboard header should have six ANSI Shadow rows")
assert(header_row - 1 == dashboard.row, "dashboard did not apply its centered vertical offset")
local content_height = #dashboard.lines - dashboard.row
local expected_row = math.max(math.floor((dashboard._size.height - content_height) / 2), 0)
assert(dashboard.row == expected_row, "dashboard content is not vertically centered")
for index = 1, 6 do
	local name = "MayonDashboardGradient" .. index
	local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
	assert(hl.fg, "missing dashboard gradient highlight: " .. name)
	assert(not vim.tbl_contains(gradient_colors, hl.fg), "dashboard gradient colors should differ on every row")
	gradient_colors[#gradient_colors + 1] = hl.fg
end
local palette = require("mayon.generated").palette
local original_blue = palette.blue
palette.blue = "#123456"
vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "dashboard-palette-refresh-test" })
assert(vim.api.nvim_get_hl(0, { name = "MayonDashboardGradient1", link = false }).fg == 0x123456)
palette.blue = original_blue
vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "dashboard-palette-restore-test" })
local file_segments = require("mayon.ui.dashboard").config().formats.file({
	file = vim.env.NVIM_CONFIG_DIR .. "/lua/mayon/config/init.lua",
}, { width = 40 })
assert(file_segments[1][1] == "init.lua", "recent file should lead with the filename")
assert(file_segments[2].hl == "MayonDashboardMuted", "recent file parent path should be dimmed")
assert(file_segments[2][1]:find("mayon/config", 1, true), "recent file should show its project-relative parent")
local root_fixture = vim.fn.tempname()
vim.fn.mkdir(root_fixture, "p")
vim.fn.writefile({ "[project]", 'name = "dashboard-fixture"' }, root_fixture .. "/pyproject.toml")
local root_file = require("mayon.ui.dashboard").config().formats.file({
	file = root_fixture .. "/pyproject.toml",
}, { width = 40 })
assert(root_file[2][1] == "  .", "project-root files should show '.' as their parent")

local real_picker = snacks.picker
local seen = {}
snacks.picker = setmetatable({}, {
	__index = function(_, source)
		return function()
			seen[source] = true
		end
	end,
})
local picker_mappings = {
	{ "<leader><leader>", "smart" },
	{ "<leader>/", "grep" },
	{ "<leader>,", "buffers" },
	{ "<leader>fr", "recent" },
	{ "<leader>fp", "projects" },
	{ "<leader>ss", "lsp_symbols" },
	{ "<leader>sS", "lsp_workspace_symbols" },
	{ "<leader>sh", "help" },
	{ "<leader>sk", "keymaps" },
	{ "<leader>sd", "diagnostics" },
	{ "<leader>sc", "command_history" },
	{ "<leader>s.", "resume" },
}
for _, spec in ipairs(picker_mappings) do
	local mapping = vim.fn.maparg(spec[1], "n", false, true)
	assert(type(mapping.callback) == "function", "missing picker entry: " .. spec[1])
	mapping.callback()
end
local config_picker = vim.fn.maparg("<leader>fc", "n", false, true)
assert(type(config_picker.callback) == "function", "missing config file picker")
config_picker.callback()
snacks.picker = real_picker
for _, source in ipairs({
	"smart",
	"grep",
	"buffers",
	"recent",
	"projects",
	"lsp_symbols",
	"lsp_workspace_symbols",
	"help",
	"diagnostics",
	"keymaps",
	"command_history",
	"resume",
}) do
	assert(seen[source], source)
end
assert(seen.files, "config picker must use the files source")
local picker = snacks.picker.files({ cwd = vim.env.NVIM_CONFIG_DIR, show_delay = 0 })
assert(
	vim.wait(2000, function()
		return #picker:items() > 0
	end),
	"file picker finder did not finish"
)
assert(#picker:items() > 0, "file picker found no config files")
picker:close()
local explorer = snacks.explorer({ cwd = vim.env.NVIM_CONFIG_DIR, show_delay = 0 })
assert(
	require("snacks.explorer.actions").trash == require("mayon.features.fileops").trash,
	"first explorer must install the guarded trash action"
)
assert(
	snacks.rename.rename_file == require("mayon.features.fileops").rename_file,
	"first explorer must preserve guarded rename"
)
explorer:close()

local file = vim.fn.tempname() .. ".lua"
vim.fn.writefile({ "local function test()", "  local a = 1", "  return a", "end", "return test()" }, file)
vim.cmd.edit(file)
assert(vim.bo.filetype == "lua")
assert(vim.wo.foldmethod == "expr")
assert(vim.wo.foldexpr == "v:lua.vim.treesitter.foldexpr()")
assert(vim.wo.foldtext:find("mayon.features.folds", 1, true))
vim.wo.foldlevel = 0
vim.cmd.normal({ "zM", bang = true })
assert(vim.fn.foldclosed(1) == 1, "native treesitter folding failed")
assert(vim.fn.foldtextresult(1):find("lines", 1, true), "fold summary lacks line count")
vim.cmd.normal({ "zR", bang = true })
assert(vim.fn.foldclosed(1) == -1)
vim.fn.delete(file)
vim.cmd.colorscheme("onedark")
for _, group in ipairs({
	"MayonDashboardBlue",
	"MayonDashboardCyan",
	"OilDir",
	"RainbowDelimiterBlue",
	"InclineNormal",
	"SatelliteBar",
	"TinyInlineDiagnosticVirtualTextError",
	"TodoFgTODO",
	"LspInlineCompletion",
	"MinuetVirtualText",
	"PmenuKind",
	"PmenuExtra",
	"PmenuSbar",
	"PmenuThumb",
	"DiffAdd",
	"DiffChange",
	"DiffText",
	"DiffDelete",
}) do
	local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
	assert(next(hl), "missing theme group: " .. group)
end
local palette = require("mayon.generated").palette
for _, name in ipairs({
	"TinyInlineDiagnosticVirtualTextError",
	"TinyInlineDiagnosticVirtualTextErrorCursorLine",
	"TinyInlineInvDiagnosticVirtualTextErrorNoBg",
}) do
	assert(
		vim.api.nvim_get_hl(0, { name = name, link = false }).fg == tonumber(palette.brightFg:sub(2), 16),
		"diagnostic body must remain brightFg after colorscheme reload: " .. name
	)
end
local inline = vim.api.nvim_get_hl(0, { name = "LspInlineCompletion", link = false })
assert(inline.fg == tonumber(palette.muted:sub(2), 16) and inline.italic, "AI ghost text must use muted italic")
local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
assert(normal.bg == tonumber(palette.deep:sub(2), 16), "editor surface must use generated deep")

-- The right rail summarizes actionable diagnostics, independently of Git.
require("lz.n").trigger_load("satellite.nvim")
local handlers = require("satellite.handlers")
handlers.init()
local diagnostic_handler
for _, handler in ipairs(handlers.handlers) do
	assert(handler.name ~= "gitsigns" or not handler:enabled(), "Git marks duplicate the left gutter")
	if handler.name == "diagnostic" then
		diagnostic_handler = handler
	end
end
assert(diagnostic_handler and diagnostic_handler:enabled())
local rail_ns = vim.api.nvim_create_namespace("SatelliteDiagnosticTest")
local rail_buf, rail_win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
local function rail_marks()
	local marks
	require("satellite.async").run(function()
		marks = diagnostic_handler.update(rail_buf, rail_win)
	end)
	assert(
		vim.wait(1000, function()
			return marks ~= nil
		end),
		"Satellite diagnostic update timed out"
	)
	return marks
end
local function set_diagnostics(severities)
	local items = {}
	for _, severity in ipairs(severities) do
		items[#items + 1] = { lnum = 0, col = 0, message = "rail fixture", severity = severity }
	end
	vim.diagnostic.set(rail_ns, rail_buf, items)
end
local severity = vim.diagnostic.severity
set_diagnostics({ severity.INFO, severity.HINT })
assert(#rail_marks() == 0, "low severity diagnostics should not clutter the rail")
set_diagnostics({ severity.ERROR, severity.WARN, severity.INFO, severity.HINT })
local marks = rail_marks()
assert(#marks == 1 and marks[1].symbol == "=", "rail must count only error/warning diagnostics")
assert(marks[1].highlight == "SatelliteDiagnosticError", "rail must retain the highest severity")
vim.diagnostic.reset(rail_ns, rail_buf)
assert(#rail_marks() == 0, "a buffer without diagnostics should have no diagnostic rail marks")
assert(vim.v.errmsg == "", vim.v.errmsg)
print("Lazy setup, dashboard, unified pickers, folds and palette groups passed")
