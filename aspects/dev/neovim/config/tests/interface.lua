-- Decorations are lazy in production; load their cold-start specs and verify
-- the locked plugin options rather than relying on a manually opened session.
require("lz.n").trigger_load({ "nvim-highlight-colors", "tiny-inline-diagnostic.nvim", "tiny-glimmer.nvim" })
local color_options = require("mayon.ui.extras").color_options()
assert(color_options.render == "virtual" and color_options.virtual_symbol == "■")
local early_palette = require("mayon.generated").palette
local early_normal_nc = vim.api.nvim_get_hl(0, { name = "NormalNC", link = false })
assert(
	early_normal_nc.bg
		== tonumber(require("mayon.ui.theme").blend(early_palette.deep, early_palette.bg, 0.42):sub(2), 16),
	"startup inactive editor islands should sit between deep and the active editor surface"
)
assert(color_options.enable_named_colors == false, "named colors must not recolor prose/comments")
assert(color_options.enable_hex and color_options.enable_rgb and color_options.enable_var_usage)
assert(color_options.enable_tailwind, "Tailwind utility colors should receive swatches")
assert(not package.loaded.colorizer, "the background-colorizer plugin should be removed")
local inline_diagnostic = require("tiny-inline-diagnostic")
assert(inline_diagnostic.config.preset == "modern", "inline diagnostics should use the capsule preset")
assert(inline_diagnostic.config.signs.arrow == "", "inline diagnostics should omit the large arrow")
assert(inline_diagnostic.config.signs.left == "" and inline_diagnostic.config.signs.right == "")
assert(inline_diagnostic.config.options.show_code == false)
assert(inline_diagnostic.config.options.show_all_diags_on_cursorline)
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
assert(lines:find("mayon.nvim", 1, true), "dashboard title did not render")
assert(lines:find("━━━", 1, true), "dashboard blue rule did not render")
for _, label in ipairs({
	"查找文件",
	"全文搜索",
	"最近文件",
	"恢复会话",
	"项目列表",
	"Claude Code",
	"新建文件",
	"配置",
}) do
	assert(lines:find(label, 1, true), "dashboard action missing: " .. label)
end
for _, key in ipairs({ "f", "g", "r", "s", "p", "a", "n", "c" }) do
	assert(lines:find(" " .. key .. " ", 1, true), "dashboard action keycap missing: " .. key)
end
local paired_actions = false
for _, line in ipairs(rendered) do
	if line:find("查找文件", 1, true) and line:find("全文搜索", 1, true) then
		paired_actions = true
	end
end
assert(paired_actions, "dashboard actions should use a two-column grid")
assert(lines:find("RECENT", 1, true) and lines:find("PROJECTS", 1, true), "dashboard groups did not render")
assert(lines:find("recent-note.txt", 1, true), "dashboard did not render a recent file")
assert(lines:find("plugins", 1, true) and lines:find("nvim ", 1, true), "dashboard footer lacks runtime details")
assert(lines:find("copilot", 1, true), "dashboard footer lacks Copilot status")
assert(not lines:find("██", 1, true), "dashboard should not render a large ASCII logo")
assert(
	not lines:find("%f[%a]file%f[%A]") and not lines:find("%f[%a]directory%f[%A]"),
	"dashboard exposed an icon fallback label"
)
assert(vim.bo[dashboard.buf].filetype == "snacks_dashboard")
local find_mapping = vim.fn.maparg("f", "n", false, true)
assert(type(find_mapping.callback) == "function", "dashboard file-search key mapping is missing")
local original_files, file_search_called = snacks.picker.files, false
snacks.picker.files = function()
	file_search_called = true
end
find_mapping.callback()
snacks.picker.files = original_files
assert(file_search_called, "dashboard file-search mapping did not route to Snacks")
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
assert(
	vim.api.nvim_get_hl(0, { name = "MayonDashboardSelection", link = false }).bg
		== tonumber(palette.selection:sub(2), 16),
	"dashboard selection should use the palette selection surface"
)
local keycap = vim.api.nvim_get_hl(0, { name = "MayonDashboardKey", link = false })
assert(
	keycap.fg == tonumber(palette.muted:sub(2), 16) and keycap.bg == tonumber(palette.surface:sub(2), 16),
	"dashboard keycaps should use the muted surface style"
)
local active_keycap = vim.api.nvim_get_hl(0, { name = "MayonDashboardKeyActive", link = false })
assert(
	active_keycap.fg == tonumber(palette.blue:sub(2), 16) and active_keycap.bg == tonumber(palette.selection:sub(2), 16),
	"selected dashboard keycaps should use blue on the selection surface"
)
local file_segments = dashboard_config.formats.file({ file = recent_file }, { width = 40 })
assert(vim.trim(file_segments[1][1]) == "recent-note.txt", "recent file should lead with its filename")
assert(file_segments[3].hl == "MayonDashboardMuted", "recent file parent path should be muted")
assert(file_segments[3][1]:find(vim.fn.fnamemodify(vim.fs.dirname(recent_file), ":t"), 1, true))
local dashboard_file_icon = dashboard_config.formats.icon({ icon = "file", file = recent_file })
local expected_dashboard_icon = require("mayon.ui.icons").get(recent_file)
assert(
	dashboard_file_icon[1] == expected_dashboard_icon
		and dashboard_file_icon[1] ~= "  "
		and dashboard_file_icon.hl:match("^DevIcon"),
	"recent files should display their colored devicon"
)
assert(
	dashboard_config.formats.icon({ icon = "directory" })[1] == "▸ ",
	"project directories should use the blue arrow"
)
local root_fixture = vim.fn.tempname()
vim.fn.mkdir(root_fixture, "p")
vim.fn.writefile({ "[project]", 'name = "dashboard-fixture"' }, root_fixture .. "/pyproject.toml")
local root_file = require("mayon.ui.dashboard").config().formats.file({
	file = root_fixture .. "/pyproject.toml",
}, { width = 40 })
assert(root_file[3][1] == ".", "project-root files should show '.' as their parent")

-- Session restore must initialize the lazy feature even before any file read.
local session_fixture = vim.fn.stdpath("state") .. "/sessions/dashboard-restore.vim"
vim.fn.mkdir(vim.fs.dirname(session_fixture), "p")
vim.fn.writefile({ "let g:mayon_dashboard_restored = 1" }, session_fixture)
vim.fn.maparg("s", "n", false, true).callback()
assert(vim.g.mayon_dashboard_restored == 1, "dashboard session action did not initialize lazy sessions")
vim.fn.delete(session_fixture)

-- A dashboard may remain visible while another split owns focus. Resizing
-- must style and bind only the dashboard, then recent-file Enter must work.
vim.api.nvim_set_current_win(dashboard.win)
vim.fn.maparg("l", "n", false, true).callback()
local right_column = vim.api.nvim_win_get_cursor(dashboard.win)[2]
vim.fn.maparg("j", "n", false, true).callback()
assert(
	vim.api.nvim_win_get_cursor(dashboard.win)[2] >= right_column - 4,
	"vertical grid movement lost the right column"
)
vim.cmd.vnew()
local ordinary_win, ordinary_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
vim.bo.filetype = "text"
vim.keymap.set("n", "q", function() end, { buffer = ordinary_buf, desc = "ordinary-q" })
local ordinary_highlight = vim.wo.winhighlight
vim.api.nvim_win_set_width(dashboard.win, 70)
vim.api.nvim_exec_autocmds("VimResized", {})
vim.wait(50)
assert(vim.fn.maparg("q", "n", false, true).desc == "ordinary-q", "dashboard resize replaced a document mapping")
assert(vim.wo[ordinary_win].winhighlight == ordinary_highlight, "dashboard resize restyled a document")
local recent_row
for index, line in ipairs(vim.api.nvim_buf_get_lines(dashboard.buf, 0, -1, false)) do
	if line:find("recent-note.txt", 1, true) then
		recent_row = index
		break
	end
end
assert(
	recent_row,
	"resize lost the recent-file row: " .. vim.inspect(vim.api.nvim_buf_get_lines(dashboard.buf, 0, -1, false))
)
vim.api.nvim_win_set_cursor(dashboard.win, { recent_row, 0 })
vim.api.nvim_win_call(dashboard.win, function()
	vim.fn.maparg("<cr>", "n", false, true).callback()
end)
assert(
	vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(dashboard.win)) == recent_file,
	"recent-file Enter failed after an unfocused resize"
)
assert(vim.o.showtabline == 2, "leaving a manually opened dashboard should restore tabs")
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
assert(worktree_lines:find("visual-fixture", 1, true), "absolute worktree gitdir lost its branch")
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
	"MayonFrame",
	"MayonIsland",
	"MiniMapNormal",
	"MiniMapSymbolLine",
	"MiniMapSymbolCount",
	"MiniMapSymbolView",
	"MayonToolbar",
	"MayonToolRail",
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
local palette = require("mayon.generated").palette
local tiny_error = vim.api.nvim_get_hl(0, { name = "TinyInlineDiagnosticVirtualTextError", link = false })
assert(
	tiny_error.fg == tonumber(require("mayon.ui.theme").blend(palette.red, palette.fg, 0.58):sub(2), 16)
		and tiny_error.bg == tonumber(require("mayon.ui.theme").blend(palette.red, palette.bg, 0.12):sub(2), 16),
	"diagnostic capsule should use a soft severity tint and readable severity text"
)
local cursor_error = vim.api.nvim_get_hl(0, { name = "TinyInlineDiagnosticVirtualTextErrorCursorLine", link = false })
assert(cursor_error.fg == tiny_error.fg and cursor_error.bg == tiny_error.bg)
local no_bg = vim.api.nvim_get_hl(0, { name = "TinyInlineInvDiagnosticVirtualTextErrorNoBg", link = false })
assert(no_bg.fg == tonumber(palette.muted:sub(2), 16))
local inline = vim.api.nvim_get_hl(0, { name = "LspInlineCompletion", link = false })
assert(inline.fg == tonumber(palette.muted:sub(2), 16) and inline.italic, "AI ghost text must use muted italic")
local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
assert(normal.bg == tonumber(palette.bg:sub(2), 16), "editor surface must use generated bg")
assert(require("mayon.ui.theme").frame_color() == "#090a0c", "frame color should be derived from palette black")
assert(
	vim.api.nvim_get_hl(0, { name = "MiniMapNormal", link = false }).fg
		== tonumber(require("mayon.ui.theme").blend(palette.muted, palette.bg, 0.30):sub(2), 16),
	"mini.map base glyphs should be muted against the editor island"
)
assert(
	vim.api.nvim_get_hl(0, { name = "MiniMapSymbolView", link = false }).bg
		== tonumber(require("mayon.ui.theme").blend(palette.blue, palette.bg, 0.12):sub(2), 16),
	"mini.map viewport should use a restrained blue tint"
)
assert(require("mayon.ui.theme").mode_highlight("i") == "MayonModeBlockInsert")
assert(require("mayon.ui.theme").mode_highlight("v") == "MayonModeBlockVisual")
local current_win = vim.api.nvim_get_current_win()
vim.cmd.vsplit()
assert(
	vim.wo[current_win].winhighlight:find("CursorLine:NormalNC", 1, true),
	"inactive document windows should hide the current-line highlight"
)
vim.cmd.close()
assert(
	not vim.wo[current_win].winhighlight:find("CursorLine:NormalNC", 1, true),
	"the focused editor should restore its current-line highlight"
)
assert(not package.loaded.satellite, "the removed satellite UI must stay unloaded")
assert(vim.v.errmsg == "", vim.v.errmsg)
print("Lazy setup, dashboard, unified pickers, folds and palette groups passed")

assert(vim.wo.cursorline and vim.wo.cursorlineopt == "both", "leaving dashboard must restore editor line highlight")
