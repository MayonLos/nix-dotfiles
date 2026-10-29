-- Decorations are lazy in production; load their cold-start specs and verify
-- the locked plugin options rather than relying on a manually opened session.
require("lz.n").trigger_load({ "nvim-highlight-colors", "tiny-inline-diagnostic.nvim", "tiny-glimmer.nvim" })
local color_options = require("mayon.ui.extras").color_options()
assert(color_options.render == "virtual" and color_options.virtual_symbol == "■")
local early_palette = require("mayon.generated").palette
local early_normal_nc = vim.api.nvim_get_hl(0, { name = "NormalNC", link = false })
assert(
	early_normal_nc.bg == tonumber(early_palette.bg:sub(2), 16)
		and early_normal_nc.fg == tonumber(early_palette.fg:sub(2), 16)
		and early_normal_nc.fg ~= tonumber(early_palette.brightFg:sub(2), 16),
	"inactive editor text should be dimmer on the shared editor surface"
)
assert(vim.o.showtabline == 0 and vim.o.winbar == "", "document chrome should be hidden by default")
assert(color_options.enable_named_colors == false, "named colors must not recolor prose/comments")
assert(color_options.enable_hex and color_options.enable_rgb and color_options.enable_var_usage)
assert(color_options.enable_tailwind, "Tailwind utility colors should receive swatches")
assert(not package.loaded.colorizer, "the background-colorizer plugin should be removed")
local inline_diagnostic = require("tiny-inline-diagnostic")
assert(inline_diagnostic.config.preset == "minimal", "inline diagnostics should use the quiet one-line preset")
assert(inline_diagnostic.config.signs.arrow == "", "inline diagnostics should omit the large arrow")
assert(inline_diagnostic.config.signs.left == "" and inline_diagnostic.config.signs.right == "")
assert(inline_diagnostic.config.signs.diag == "▲" and inline_diagnostic.config.transparent_bg)
assert(inline_diagnostic.config.options.show_code == false)
assert(not inline_diagnostic.config.options.show_all_diags_on_cursorline)
assert(inline_diagnostic.config.options.overflow.mode == "oneline")
local at_position = require("tiny-inline-diagnostic.filter").at_position
local inline_candidates = {
	{ lnum = 0, col = 2, end_col = 4, severity = vim.diagnostic.severity.WARN, message = "first" },
	{ lnum = 0, col = 8, end_col = 10, severity = vim.diagnostic.severity.ERROR, message = "second" },
}
local chosen = at_position(inline_diagnostic.config, inline_candidates, 0, 14)
assert(#chosen == 1 and chosen[1].message == "second", "multiple diagnostics must remain a single inline message")
assert(#inline_candidates == 2, "inline selection must not remove diagnostic data")
local motion = require("mayon.ui.motion").config()
assert(motion.overwrite.yank.enabled and motion.overwrite.paste.enabled)
assert(motion.overwrite.search.enabled and motion.overwrite.undo.enabled and motion.overwrite.redo.enabled)
assert(motion.animations.fade.max_duration <= 300 and motion.animations.reverse_fade.max_duration <= 300)
assert(motion.enabled == not require("mayon.ui.motion").reduced_motion())

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
local recent_file = vim.fn.tempname() .. "/recent-note.txt"
vim.fn.mkdir(vim.fs.dirname(recent_file), "p")
vim.fn.writefile({ "dashboard recent fixture" }, recent_file)
local oldfiles = vim.v.oldfiles
vim.v.oldfiles = { recent_file }
local dashboard = snacks.dashboard.open({ win = 0, buf = 0 })
local rendered = vim.api.nvim_buf_get_lines(dashboard.buf, 0, -1, false)
local lines = table.concat(rendered, "\n")
local wide_geometry = dashboard.opts
assert(wide_geometry.width == 60, "wide dashboard block should be 60 columns: " .. vim.inspect(wide_geometry))
assert(wide_geometry.col == 30, "wide dashboard block should be horizontally centered: " .. vim.inspect(wide_geometry))
vim.o.columns = 80
vim.api.nvim_exec_autocmds("VimResized", {})
vim.wait(40)
local narrow_geometry = dashboard.opts
assert(
	narrow_geometry.width == 60,
	"80-column dashboard should retain its 60-column block: " .. vim.inspect(narrow_geometry)
)
assert(narrow_geometry.col == 10, "80-column dashboard block should remain centered: " .. vim.inspect(narrow_geometry))
vim.o.columns = 120
vim.api.nvim_exec_autocmds("VimResized", {})
vim.wait(40)
assert(dashboard.opts.width == 60 and dashboard.opts.col == 30, "wide dashboard geometry should recover after resize")
assert(lines:find("Neovim", 1, true), "dashboard title did not render")
assert(
	lines:find("Recent Projects", 1, true) and lines:find("Recent Files", 1, true) and lines:find("Actions", 1, true),
	"dashboard history groups did not render"
)
for _, label in ipairs({ "Open", "Search", "New", "Config", "Quit" }) do
	assert(lines:find(label, 1, true), "dashboard action missing: " .. label)
end
assert(lines:find("recent-note.txt", 1, true), "dashboard did not render a recent file")
assert(
	not lines:find("plugins", 1, true) and not lines:find("copilot", 1, true),
	"dashboard should omit runtime counters"
)
assert(not lines:find("██", 1, true), "dashboard should not render a large ASCII logo")
assert(
	not lines:find("%f[%a]file%f[%A]") and not lines:find("%f[%a]directory%f[%A]"),
	"dashboard exposed an icon fallback label"
)
assert(vim.bo[dashboard.buf].filetype == "snacks_dashboard")
local dashboard_keys = {}
for _, item in ipairs(dashboard.items) do
	if item.key then
		dashboard_keys[item.key] = item.action
	end
end
for _, key in ipairs({ "f", "g", "n", "c", "q", "r", "s", "p", "a" }) do
	assert(dashboard_keys[key], "dashboard shortcut should remain callable: " .. key)
end
assert(dashboard_keys.q == ":qa", "dashboard quit shortcut should route to :qa")
for _, key in ipairs({ "f", "g", "n", "c", "q" }) do
	assert(lines:find(" " .. key .. " ", 1, true), "visible dashboard shortcut missing: " .. key)
end
for _, key in ipairs({ "r", "s", "p", "a" }) do
	assert(not lines:find(" " .. key .. " ", 1, true), "legacy dashboard shortcut should stay hidden: " .. key)
end
local action_labels = { Open = "f", Search = "g", New = "n", Config = "c", Quit = "q" }
local key_column
local name_column
local function display_column(line, value)
	local start = assert(line:find(value, 1, true), "missing text while measuring dashboard column: " .. value)
	return vim.fn.strdisplaywidth(line:sub(1, start - 1))
end
for label, key in pairs(action_labels) do
	local action_line
	for _, line in ipairs(rendered) do
		if line:find(label, 1, true) then
			action_line = line
			break
		end
	end
	assert(action_line, "dashboard action row missing: " .. label)
	local key_start = action_line:find(" " .. key .. " ", 1, true)
	assert(key_start, "dashboard action row has no visible shortcut: " .. label)
	local current_key_column = vim.fn.strdisplaywidth(action_line:sub(1, key_start - 1))
	key_column = key_column or current_key_column
	assert(current_key_column == key_column, "dashboard shortcut column is not right aligned: " .. label)
	local current_name_column = display_column(action_line, label)
	name_column = name_column or current_name_column
	assert(current_name_column == name_column, "dashboard action labels do not share a text column: " .. label)
end
local function dashboard_row(text)
	for _, line in ipairs(rendered) do
		if line:find(text, 1, true) then
			return line
		end
	end
	error("dashboard row missing: " .. text)
end
local heading_column = display_column(dashboard_row("Neovim"), "Neovim")
for _, heading in ipairs({ "Recent Projects", "Recent Files", "Actions" }) do
	assert(
		display_column(dashboard_row(heading), heading) == heading_column,
		"dashboard heading alignment mismatch: " .. heading
	)
end
assert(
	vim.api.nvim_get_hl(0, { name = "MayonDashboardNormal", link = false }).bg
		== tonumber(require("mayon.generated").palette.bg:sub(2), 16),
	"dashboard background should match the editor"
)
local palette = require("mayon.generated").palette
local original_blue = palette.blue
palette.blue = "#123456"
vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "dashboard-palette-refresh-test" })
assert(vim.api.nvim_get_hl(0, { name = "MayonDashboardBlue", link = false }).fg == 0x123456)
palette.blue = original_blue
vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "dashboard-palette-restore-test" })
local dashboard_config = require("mayon.ui.dashboard").config()
assert(dashboard_config.preset.keys[1].key == "q", "quit should remain in the dashboard footer hint")
local file_segments = dashboard_config.formats.file({ file = recent_file }, { width = 40 })
assert(file_segments.hl == "MayonDashboardMuted", "recent file path should be muted")
assert(file_segments[1]:find("recent-note.txt", 1, true), "recent file path should include its filename")
local dashboard_file_icon = dashboard_config.formats.icon({ icon = "file", file = recent_file })
local expected_dashboard_icon = require("mayon.ui.icons").get(recent_file)
assert(
	dashboard_file_icon[1] == vim.trim(expected_dashboard_icon)
		and dashboard_file_icon[1] ~= ""
		and dashboard_file_icon.hl:match("^DevIcon"),
	"recent files should display their colored devicon"
)
assert(
	dashboard_config.formats.icon({ icon = "directory" }).width == 2,
	"project icons should reserve a consistent two-cell column"
)
local root_fixture = vim.fn.tempname()
vim.fn.mkdir(root_fixture, "p")
vim.fn.writefile({ "[project]", 'name = "dashboard-fixture"' }, root_fixture .. "/pyproject.toml")
local root_file = require("mayon.ui.dashboard").config().formats.file({
	file = root_fixture .. "/pyproject.toml",
}, { width = 40 })
assert(
	root_file[1]:match("[^/]+/pyproject%.toml$"),
	"recent path should be short and relative rather than absolute: " .. vim.inspect(root_file)
)

local function assert_dashboard_selection(row)
	vim.api.nvim_win_set_cursor(dashboard.win, { row, 0 })
	vim.api.nvim_exec_autocmds("CursorMoved", { buffer = dashboard.buf })
	vim.wait(30)
	local marks = vim.api.nvim_buf_get_extmarks(
		dashboard.buf,
		vim.api.nvim_get_namespaces().MayonDashboardSelection,
		{ row - 1, 0 },
		{ row - 1, -1 },
		{ details = true }
	)
	local selected, rail = false, false
	local line = vim.api.nvim_buf_get_lines(dashboard.buf, row - 1, row, false)[1] or ""
	for _, mark in ipairs(marks) do
		local details = mark[4]
		selected = selected
			or (
				details.hl_group == "MayonDashboardSelection"
				and mark[3] == dashboard.opts.col
				and details.end_col == #line
			)
		rail = rail
			or (
				details.virt_text
				and details.virt_text[1]
				and details.virt_text[1][1] == "▎"
				and details.virt_text[1][2] == "MayonDashboardRail"
			)
	end
	assert(
		selected,
		"selected dashboard row lacks bounded background: "
			.. vim.inspect({ marks = marks, line = line, col = dashboard.opts.col, items = dashboard.items })
	)
	assert(rail, "selected dashboard row lacks its blue rail: " .. vim.inspect(marks))
end
local open_row
for _, item in ipairs(dashboard.items) do
	if item.key == "f" then
		open_row = item._.row
		break
	end
end
assert(open_row, "dashboard Open row metadata is missing")
assert_dashboard_selection(open_row)

-- Session restore must initialize the lazy feature even before any file read.
local session_fixture = vim.fn.stdpath("state") .. "/sessions/dashboard-restore.vim"
vim.fn.mkdir(vim.fs.dirname(session_fixture), "p")
vim.fn.writefile({ "let g:mayon_dashboard_restored = 1" }, session_fixture)
vim.fn.maparg("s", "n", false, true).callback()
assert(vim.g.mayon_dashboard_restored == 1, "dashboard session action did not initialize lazy sessions")
vim.fn.delete(session_fixture)

-- A dashboard may remain visible while another split owns focus. Native Snacks
-- movement remains available and recent-file Enter opens the selected item.
vim.api.nvim_set_current_win(dashboard.win)
vim.api.nvim_win_set_cursor(dashboard.win, { 1, 0 })
vim.api.nvim_win_call(dashboard.win, function()
	vim.cmd.normal({ args = { "j" }, bang = true })
end)
assert(vim.api.nvim_win_get_cursor(dashboard.win)[1] == 2, "native dashboard j movement should advance one row")
local recent_row
for index, line in ipairs(vim.api.nvim_buf_get_lines(dashboard.buf, 0, -1, false)) do
	if line:find("recent-note.txt", 1, true) then
		recent_row = index
		break
	end
end
assert(recent_row, "dashboard recent-file row metadata is missing before resize")
vim.api.nvim_win_set_cursor(dashboard.win, { recent_row, 0 })
vim.wait(30)
assert_dashboard_selection(recent_row)
vim.cmd.vnew()
local ordinary_win, ordinary_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
vim.bo.filetype = "text"
vim.keymap.set("n", "q", function() end, { buffer = ordinary_buf, desc = "ordinary-q" })
local ordinary_highlight = vim.wo.winhighlight
vim.api.nvim_exec_autocmds("VimResized", {})
vim.wait(50)
assert(vim.fn.maparg("q", "n", false, true).desc == "ordinary-q", "dashboard resize replaced a document mapping")
assert(vim.wo[ordinary_win].winhighlight == ordinary_highlight, "dashboard resize restyled a document")
recent_row = vim.api.nvim_win_get_cursor(dashboard.win)[1]
local selected_after_resize = vim.api.nvim_buf_get_lines(dashboard.buf, recent_row - 1, recent_row, false)[1] or ""
assert(
	selected_after_resize:find("recent-note.txt", 1, true),
	"resize did not preserve the selected recent file: " .. vim.inspect(selected_after_resize)
)
assert_dashboard_selection(recent_row)
vim.api.nvim_win_set_cursor(dashboard.win, { recent_row, 0 })
vim.api.nvim_win_call(dashboard.win, function()
	vim.fn.maparg("<cr>", "n", false, true).callback()
end)
assert(
	vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(dashboard.win)) == recent_file,
	"recent-file Enter failed after an unfocused resize"
)
assert(vim.o.showtabline == 0, "leaving the dashboard should keep document tabs hidden")
vim.api.nvim_win_close(ordinary_win, true)

-- Worktrees use an absolute gitdir; it must render a branch without reading
-- or changing any real worktree metadata.
local original_cwd = vim.fn.getcwd()
local worktree, metadata = vim.fn.tempname(), vim.fn.tempname()
vim.fn.mkdir(worktree, "p")
vim.fn.mkdir(metadata, "p")
vim.fn.writefile({ "gitdir: " .. metadata }, worktree .. "/.git")
vim.fn.writefile({ "ref: refs/heads/visual-fixture" }, metadata .. "/HEAD")
vim.fn.chdir(worktree)
local worktree_dashboard = snacks.dashboard.open({ win = 0, buf = 0 })
local worktree_lines = table.concat(vim.api.nvim_buf_get_lines(worktree_dashboard.buf, 0, -1, false), "\n")
assert(not worktree_lines:find("visual-fixture", 1, true), "dashboard should not render a persistent branch header")
vim.fn.chdir(original_cwd)
vim.v.oldfiles = oldfiles

local real_picker = snacks.picker
local seen = {}
snacks.picker = setmetatable({}, {
	__call = function(_, opts)
		assert(vim.tbl_contains(opts.multi, "files") and vim.tbl_contains(opts.multi, "keymaps"))
		seen.everywhere = true
	end,
	__index = function(_, source)
		return function()
			seen[source] = true
		end
	end,
})
local picker_mappings = {
	{ "<leader><leader>", "everywhere" },
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
	"everywhere",
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
for _, group in ipairs({
	"MayonDashboardBlue",
	"MayonDashboardMuted",
	"OilDir",
	"RainbowDelimiterBlue",
	"InclineNormal",
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
assert(vim.o.tabline == "", "no persistent toolbar should be installed")
local palette = require("mayon.generated").palette
for _, group in ipairs({ "FloatTitle", "MayonPopupTitle" }) do
	local title = vim.api.nvim_get_hl(0, { name = group, link = false })
	assert(title.fg == tonumber(palette.muted:sub(2), 16), "floating titles should use muted text: " .. group)
	assert(title.bg == tonumber(palette.deep:sub(2), 16) and not title.bold, "floating title style mismatch: " .. group)
end
local tiny_error = vim.api.nvim_get_hl(0, { name = "TinyInlineDiagnosticVirtualTextError", link = false })
assert(
	tiny_error.fg == tonumber(require("mayon.ui.theme").blend(palette.yellow, palette.bg, 0.62):sub(2), 16)
		and tiny_error.italic
		and not tiny_error.bg,
	"inline diagnostics should be pale, italic text without a capsule background"
)
local cursor_error = vim.api.nvim_get_hl(0, { name = "TinyInlineDiagnosticVirtualTextErrorCursorLine", link = false })
assert(cursor_error.fg == tiny_error.fg and cursor_error.italic and not cursor_error.bg)
local no_bg = vim.api.nvim_get_hl(0, { name = "TinyInlineInvDiagnosticVirtualTextErrorNoBg", link = false })
assert(no_bg.fg == tiny_error.fg and no_bg.italic and not no_bg.bg)
local inline = vim.api.nvim_get_hl(0, { name = "LspInlineCompletion", link = false })
assert(inline.fg == tonumber(palette.muted:sub(2), 16) and inline.italic, "AI ghost text must use muted italic")
local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
assert(normal.bg == tonumber(palette.bg:sub(2), 16), "editor surface must use generated bg")
local function luminance(hex)
	local channels = {}
	for _, offset in ipairs({ 2, 4, 6 }) do
		local channel = tonumber(hex:sub(offset, offset + 1), 16) / 255
		channels[#channels + 1] = channel <= 0.04045 and channel / 12.92 or ((channel + 0.055) / 1.055) ^ 2.4
	end
	return 0.2126 * channels[1] + 0.7152 * channels[2] + 0.0722 * channels[3]
end
local visual = vim.api.nvim_get_hl(0, { name = "Visual", link = false })
local visual_fg = string.format("#%06x", visual.fg)
local visual_bg = string.format("#%06x", visual.bg)
local contrast = (luminance(visual_fg) + 0.05) / (luminance(visual_bg) + 0.05)
assert(visual.bg == tonumber(require("mayon.ui.theme").blend(palette.blue, palette.bg, 0.14):sub(2), 16))
assert(contrast >= 4.5, "visual selection text contrast must meet WCAG AA for normal text")
local inactive_bg = string.format("#%06x", early_normal_nc.bg)
local inactive_fg = string.format("#%06x", early_normal_nc.fg)
local inactive_luminance, inactive_surface_luminance = luminance(inactive_fg), luminance(inactive_bg)
local inactive_contrast = (inactive_luminance + 0.05) / (inactive_surface_luminance + 0.05)
assert(inactive_contrast >= 4.5, "inactive editor text contrast must meet WCAG AA for normal text")
local search = vim.api.nvim_get_hl(0, { name = "Search", link = false })
assert(search.bg == tonumber(require("mayon.ui.theme").blend(palette.orange, palette.bg, 0.22):sub(2), 16))
local inc_search = vim.api.nvim_get_hl(0, { name = "IncSearch", link = false })
local cur_search = vim.api.nvim_get_hl(0, { name = "CurSearch", link = false })
assert(inc_search.bg == tonumber(palette.orange:sub(2), 16) and inc_search.fg == tonumber(palette.deep:sub(2), 16))
assert(cur_search.bg == inc_search.bg and cur_search.fg == inc_search.fg)
local matchparen = vim.api.nvim_get_hl(0, { name = "MatchParen", link = false })
assert(matchparen.bold and matchparen.underline and not matchparen.bg, "matching brackets should have no filled block")
for _, group in ipairs({ "LspReferenceText", "LspReferenceRead", "LspReferenceWrite" }) do
	local words = vim.api.nvim_get_hl(0, { name = group, link = false })
	assert(words.underline and not words.bg and words.sp, "symbol references should use a quiet underline")
end
local cursor = vim.api.nvim_get_hl(0, { name = "Cursor", link = false })
assert(cursor.bg == tonumber(palette.blue:sub(2), 16), "Normal mode cursor should use blue")
assert(vim.o.guicursor:find("n:block-Cursor", 1, true), "Normal cursor should be a block")
assert(vim.o.guicursor:find("i-ci:ver25-Cursor", 1, true), "Insert cursor should be a beam")
assert(vim.o.guicursor:find("r-cr-o:hor20-Cursor", 1, true), "Replace cursor should be an underline")
local theme = require("mayon.ui.theme")
for mode, color in pairs({
	n = palette.blue,
	i = palette.green,
	v = palette.blue,
	R = palette.red,
	c = palette.yellow,
}) do
	assert(theme.mode_color(mode) == tonumber(color:sub(2), 16), "mode cursor color mismatch: " .. mode)
end
for group, color in pairs({ DiffAdd = palette.green, DiffChange = palette.blue, DiffDelete = palette.red }) do
	local diff = vim.api.nvim_get_hl(0, { name = group, link = false })
	assert(diff.bg == tonumber(theme.blend(color, palette.bg, 0.12):sub(2), 16), "diff tint mismatch: " .. group)
end
for group, color in pairs({ GitSignsAdd = palette.green, GitSignsChange = palette.blue, GitSignsDelete = palette.red }) do
	local sign = vim.api.nvim_get_hl(0, { name = group, link = false })
	assert(sign.fg == tonumber(color:sub(2), 16), "Git marker and diff hue mismatch: " .. group)
end
assert(
	vim.api.nvim_get_hl(0, { name = "DiffText", link = false }).bg
		== tonumber(theme.blend(palette.blue, palette.bg, 0.18):sub(2), 16),
	"changed diff text should have a slightly stronger blue tint"
)
local separator = vim.api.nvim_get_hl(0, { name = "WinSeparator", link = false })
assert(separator.bg == tonumber(palette.bg:sub(2), 16), "window separators should sit on the editor surface")
assert(
	separator.fg == tonumber(require("mayon.ui.theme").float_edge():sub(2), 16),
	"window separators should use the thin edge color"
)
local function_hl = vim.api.nvim_get_hl(0, { name = "@lsp.type.function", link = false })
local variable_hl = vim.api.nvim_get_hl(0, { name = "@lsp.type.variable", link = false })
local parameter_hl = vim.api.nvim_get_hl(0, { name = "@lsp.type.parameter", link = false })
local library_hl = vim.api.nvim_get_hl(0, { name = "@lsp.typemod.variable.defaultLibrary", link = false })
assert(function_hl.fg == tonumber(palette.blue:sub(2), 16), "semantic functions should follow One Dark blue")
assert(variable_hl.fg == tonumber(palette.fg:sub(2), 16), "semantic variables should use the base foreground")
assert(
	parameter_hl.fg == tonumber(palette.orange:sub(2), 16) and parameter_hl.italic,
	"semantic parameters should be orange italic"
)
assert(library_hl.fg == tonumber(palette.yellow:sub(2), 16), "default library symbols should be yellow")
assert(
	vim.api.nvim_get_hl(0, { name = "DropBarIconKindFunction", link = false }).fg == tonumber(palette.blue:sub(2), 16)
)
assert(require("mayon.ui.theme").mode_highlight("i") == "MayonModeBlockInsert")
assert(require("mayon.ui.theme").mode_highlight("v") == "MayonModeBlockVisual")
assert(vim.opt.fillchars:get().eob == " ", "empty document rows should remain quiet in inactive windows")
local current_win = vim.api.nvim_get_current_win()
vim.cmd.vsplit()
assert(
	vim.wo[current_win].winhighlight:find("CursorLine:NormalNC", 1, true),
	"inactive document windows should hide the current-line highlight"
)
assert(
	vim.wo[current_win].winhighlight:find("EndOfBuffer:NormalNC", 1, true),
	"inactive empty rows must match the document surface"
)
vim.cmd.close()
assert(
	not vim.wo[current_win].winhighlight:find("CursorLine:NormalNC", 1, true),
	"the focused editor should restore its current-line highlight"
)
assert(
	not vim.wo[current_win].winhighlight:find("EndOfBuffer:NormalNC", 1, true),
	"focused empty rows must restore the editor surface"
)
assert(not package.loaded.satellite, "the removed satellite UI must stay unloaded")
assert(vim.v.errmsg == "", vim.v.errmsg)
print("Lazy setup, dashboard, unified pickers, folds and palette groups passed")

assert(vim.wo.cursorline and vim.wo.cursorlineopt == "both", "leaving dashboard must restore editor line highlight")
