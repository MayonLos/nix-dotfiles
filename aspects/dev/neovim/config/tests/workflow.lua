-- UI contracts against real Heirline/Dropbar/Snacks, using only temporary files.
local tab = require("mayon.ui.tabline")
local initial = vim.api.nvim_get_current_buf()
assert(not vim.tbl_contains(tab.buffers(), initial), "empty placeholder occupies a tab")
vim.api.nvim_buf_set_lines(initial, 0, -1, false, { "unsaved note" })
assert(vim.tbl_contains(tab.buffers(), initial), "unsaved unnamed work was hidden")
vim.bo[initial].modified = false
local root = vim.fn.tempname()
vim.fn.mkdir(root, "p")
local path = root .. "/中文%说明.md"
vim.fn.writefile({
	"# 标题",
	"",
	string.rep("中文文档长段落与专业术语 ", 40),
	"",
	"| 列 | 值 |",
	"| --- | --- |",
	"| 词 | 字 |",
}, path)
vim.lsp.enable("marksman", false)
vim.cmd.edit(vim.fn.fnameescape(path))
assert(vim.bo.filetype == "markdown" and vim.wo.wrap, "long Markdown is clipped")
local doc, docwin = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
assert(vim.wo[docwin].winbar == "", "breadcrumbs should be hidden for ordinary documents")
assert(vim.fn.exists(":BreadcrumbsToggle") == 2, "on-demand breadcrumbs command is missing")
vim.cmd.BreadcrumbsToggle()
assert(vim.g.mayon_breadcrumbs == true, "breadcrumbs toggle did not enable the optional bar")
vim.wait(80)
assert(vim.wo[docwin].winbar ~= "", "breadcrumbs toggle did not attach a bar")
vim.cmd.BreadcrumbsToggle()
assert(
	vim.g.mayon_breadcrumbs == false and vim.wo[docwin].winbar == "",
	"breadcrumbs toggle did not restore the chrome-free editor"
)
for _, width in ipairs({ 40, 60, 80, 100, 120, 180 }) do
	vim.o.columns = width
	local status = vim.api.nvim_eval_statusline(vim.o.statusline, { maxwidth = width })
	local tabs = vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true, maxwidth = width })
	assert(status.str ~= "" and status.width <= width, "status line overflow")
	assert(tabs.str == "", "single-file editing should not render a tab toolbar")
	assert(vim.o.tabline == "", "tabline option should remain empty")
end
-- A diagnostic remains visible without making the statusline overflow narrow
-- layouts; unsaved work and close cancellation are covered below.
local attention = vim.api.nvim_create_namespace("workflow-attention")
local diagnostics = {}
diagnostics[1] = { lnum = 0, col = 0, message = "workflow fixture", severity = vim.diagnostic.severity.ERROR }
vim.diagnostic.set(attention, doc, diagnostics)
vim.bo[doc].modified, vim.bo[doc].readonly = true, true
for _, width in ipairs({ 40, 60, 80, 100, 160 }) do
	vim.o.columns = width
	vim.cmd.redrawstatus()
	local rail = vim.api.nvim_eval_statusline(vim.o.statusline, { maxwidth = width })
	assert(rail.width <= width, "diagnostics overflow the status line at " .. width .. " columns")
	if width >= 100 then
		assert(not rail.str:find("Copilot", 1, true), "idle AI provider should stay out of the statusline")
		assert(rail.str:find("●1", 1, true), "error count should use the compact red diagnostic marker")
	end
end
local ai_completion = require("mayon.features.ai_completion")
local old_busy = ai_completion.busy
ai_completion.busy = true
vim.cmd.redrawstatus()
assert(
	vim.api.nvim_eval_statusline(vim.o.statusline, { maxwidth = 160 }).str:find("…", 1, true),
	"busy AI completion should appear in the statusline"
)
ai_completion.busy = old_busy
vim.cmd.redrawstatus()
diagnostics[1].severity = vim.diagnostic.severity.WARN
vim.diagnostic.set(attention, doc, diagnostics)
vim.cmd.redrawstatus()
local warning_rail = vim.api.nvim_eval_statusline(vim.o.statusline, { maxwidth = 160 })
assert(warning_rail.str:find("▲1", 1, true), "warning count should use the compact yellow marker")
assert(not warning_rail.str:find("●1", 1, true), "warning-only status should not show an error marker")
vim.diagnostic.reset(attention, doc)
vim.bo[doc].modified, vim.bo[doc].readonly = false, false
vim.b[doc].gitsigns_status_dict = { added = 2, changed = 3, removed = 1 }
vim.cmd.redrawstatus()
local git_rail = vim.api.nvim_eval_statusline(vim.o.statusline, { maxwidth = 160, highlights = true })
for _, count in ipairs({ "+2", "~3", "-1" }) do
	assert(git_rail.str:find(count, 1, true), "Git change count missing from statusline: " .. count)
end
local git_colors = {}
for _, span in ipairs(git_rail.highlights or {}) do
	local group = vim.api.nvim_get_hl(0, { name = span.group, link = false })
	git_colors[group.fg] = true
end
local palette = require("mayon.generated").palette
for _, color in ipairs({ palette.green, palette.yellow, palette.red }) do
	assert(git_colors[tonumber(color:sub(2), 16)], "Git change counts lost a distinct severity color")
end
vim.b[doc].gitsigns_status_dict = nil

-- Search and macro state remain visible in the quiet one-line status.
local searchcount, old_hlsearch = vim.fn.searchcount, vim.v.hlsearch
vim.fn.searchcount = function()
	return { current = 3, total = 14, incomplete = 0 }
end
vim.v.hlsearch = 1
vim.cmd.redrawstatus()
local search_rail = vim.api.nvim_eval_statusline(vim.o.statusline, { maxwidth = 160 })
assert(search_rail.str:find("[3/14]", 1, true), "search count should use the [current/total] form")
vim.fn.searchcount, vim.v.hlsearch = searchcount, old_hlsearch
vim.cmd("normal! qq")
vim.cmd.redrawstatus()
local recording_rail = vim.api.nvim_eval_statusline(vim.o.statusline, { maxwidth = 160 })
assert(recording_rail.str:find("REC @q", 1, true), "macro recording should be visible as REC @q")
vim.cmd("normal! q")
vim.cmd.vnew()
local toolwin, toolbuf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
vim.bo.buftype = "nofile"
vim.bo.filetype = "snacks_picker_list"
tab.select(doc)
assert(vim.api.nvim_get_current_win() == docwin, "tab click chose the sidebar")
assert(vim.api.nvim_win_get_buf(toolwin) == toolbuf, "tab click replaced the sidebar")
vim.bo[toolbuf].filetype = "nofile"
local confirm = vim.fn.confirm
vim.api.nvim_buf_set_lines(doc, 0, -1, false, { "unsaved document" })
vim.fn.confirm = function()
	return 3
end
require("snacks").bufdelete({ buf = doc })
vim.fn.confirm = confirm
assert(vim.api.nvim_buf_is_valid(doc) and vim.bo[doc].modified, "cancel discarded unsaved work")
vim.bo[doc].modified = false
local count = #vim.api.nvim_list_wins()
require("snacks").bufdelete({ buf = doc })
assert(#vim.api.nvim_list_wins() == count, "closing a buffer destroyed the layout")
local scratch = require("mayon.features.scratch")
local note = scratch.scratch()
vim.api.nvim_buf_set_lines(note, 0, -1, false, { "temporary scratch note" })
vim.api.nvim_exec_autocmds("BufLeave", { buffer = note })
assert(
	vim.wait(1000, function()
		return not vim.bo[note].modified
	end),
	"scratch was not saved"
)
assert(vim.fn.readfile(vim.api.nvim_buf_get_name(note))[1] == "temporary scratch note")
-- Big-file classification must keep expensive syntax/completion/folds off.
local big = root .. "/large.lua"
vim.fn.writefile({ string.rep("x", 1024 * 1024 + 1) }, big)
vim.cmd.edit(vim.fn.fnameescape(big))
assert(vim.bo.filetype == "bigfile", "large-file handler did not claim the buffer")
assert(vim.b.completion == false, "completion remained enabled for a large file")
assert(vim.wo.foldmethod == "manual", "Tree-sitter overrode the large-file fold guard")
assert(not vim.treesitter.highlighter.active[vim.api.nvim_get_current_buf()], "large file started highlighting")
vim.cmd.colorscheme("onedark")
assert(
	vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg
		== tonumber(require("mayon.generated").palette.bg:sub(2), 16)
)
-- Surface colours must survive a theme reload after plugins have registered
-- their highlight groups. Text overlays must not punch holes in selected rows.
local function hl(name)
	return vim.api.nvim_get_hl(0, { name = name, link = false })
end
for _, name in ipairs({
	"NormalFloat",
	"FloatBorder",
	"FloatTitle",
}) do
	assert(
		hl(name).bg == tonumber(require("mayon.generated").palette.deep:sub(2), 16),
		name .. " has a disconnected background"
	)
end
local popup_bg = tonumber(require("mayon.generated").palette.deep:sub(2), 16)
for _, name in ipairs({ "Pmenu", "PmenuBorder", "SnacksPickerList", "SnacksPickerNormal", "WhichKeyNormal" }) do
	assert(hl(name).bg == popup_bg, name .. " should share the editor popup surface")
end
assert(hl("PmenuSel").bg == tonumber(require("mayon.generated").palette.selection:sub(2), 16))
for _, name in ipairs({ "RenderMarkdownH5", "RenderMarkdownH6" }) do
	assert(hl(name).fg == tonumber(require("mayon.generated").palette.fg:sub(2), 16))
end
-- A literal percent and multibyte names must render as text, never statusline
-- directives, at narrow widths as well as in the full workspace rail.
local display = require("mayon.ui.text")
for _, width in ipairs({ 1, 2, 5, 12, 24 }) do
	local fitted = display.fit("中文 50% notes", width)
	local rendered = vim.api.nvim_eval_statusline(fitted, { maxwidth = width })
	assert(rendered.width <= width, "display text exceeds its cell budget")
end
local literal = vim.api.nvim_eval_statusline(display.fit("中文 50% notes"), { maxwidth = 40 })
assert(literal.str == "中文 50% notes", "literal percent was interpreted as statusline syntax")
assert(vim.v.errmsg == "", vim.v.errmsg)
print("Long documents, Unicode tabs, sidebar preservation, close cancellation and scratch passed")

-- Project layout and native picker behavior are exercised in panels_picker.lua;
-- keep this workflow focused on close safety, sessions, big files and tasks.

-- Sessions keep project files while filtering listed plugin panes before
-- mksession; forcing the save here makes the same writer testable headlessly.
local sessions = require("mayon.features.sessions")
sessions.setup()
for _, buf in ipairs(vim.api.nvim_list_bufs()) do
	if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].modified then
		vim.bo[buf].modified = false
	end
end
local session_file = root .. "/session-entry.lua"
vim.fn.writefile({ "return true" }, session_file)
vim.cmd.lcd(root)
vim.cmd.edit(vim.fn.fnameescape(session_file))
vim.cmd.vnew()
local special_win, special_buf = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
vim.bo[special_buf].buftype = "nofile"
vim.bo[special_buf].filetype = "snacks_picker_list"
vim.bo[special_buf].buflisted = true
vim.api.nvim_buf_set_name(special_buf, "SnacksPickerSessionFixture")
assert(sessions.save(true), "headless session save did not report success")
assert(vim.g.mayon_session_saving == nil, "session save did not release the workspace guard")
local saved_session = table.concat(vim.fn.readfile(sessions.path()), "\n")
local session_basename = vim.fn.fnamemodify(session_file, ":t")
assert(
	saved_session:find(session_basename, 1, true),
	"project file path was not saved to the session: " .. sessions.path()
)
assert(not saved_session:find("SnacksPickerSessionFixture", 1, true), "Explorer pane leaked into the session")
assert(not saved_session:find("snacks_picker_list", 1, true), "Explorer filetype leaked into the session")
assert(vim.bo[special_buf].buflisted, "session filtering did not restore the buffer's listed state")
vim.api.nvim_win_close(special_win, true)
for _, filetype in ipairs({ "mayon_tools", "mayon_tabs" }) do
	vim.cmd.vnew()
	local special_window, special_buffer = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
	vim.bo[special_buffer].buftype = "nofile"
	vim.bo[special_buffer].filetype = filetype
	vim.bo[special_buffer].buflisted = false
	vim.api.nvim_buf_set_name(special_buffer, filetype .. "SessionFixture")
	assert(sessions.save(true), filetype .. " session save failed")
	local pane_session = table.concat(vim.fn.readfile(sessions.path()), "\n")
	assert(not pane_session:find(filetype .. "SessionFixture", 1, true), filetype .. " pane leaked into the session")
	vim.api.nvim_win_close(special_window, true)
end
vim.cmd.enew()
vim.bo.buftype = "nofile"
vim.bo.filetype = "snacks_dashboard"
assert(sessions.auto_restore(), "saved project session did not auto-restore from an empty start buffer")
assert(vim.g.mayon_session_saving == nil, "auto-restore did not release the workspace guard")
assert(vim.api.nvim_buf_get_name(0) == session_file, "auto-restore did not return to the project file")
assert(#vim.api.nvim_list_tabpages() == 1, "dashboard tab remained beside the restored project session")

-- Exercise the production boundary: one fresh Neovim writes the mksession,
-- then another fresh process restores it from the empty dashboard buffer.
local session_process_root = vim.fn.tempname()
vim.fn.mkdir(session_process_root, "p")
local process_project = session_process_root .. "/project"
local process_home = session_process_root .. "/home"
local process_state = session_process_root .. "/state"
vim.fn.mkdir(process_project, "p")
vim.fn.mkdir(process_home, "p")
vim.fn.mkdir(process_state, "p")
local process_file = process_project .. "/fresh-process.lua"
vim.fn.writefile({ "return 'fresh process'" }, process_file)
local source = debug.getinfo(sessions.setup, "S").source:sub(2)
local config_root = source:gsub("/lua/mayon/features/sessions.lua$", "")
local child_lua_path = config_root .. "/lua/?.lua;" .. config_root .. "/lua/?/init.lua;" .. package.path
local process_prefix = {
	vim.v.progpath,
	"--headless",
	"-u",
	"NONE",
	"--cmd",
	"lua package.path = " .. string.format("%q", child_lua_path),
}
local save_script = session_process_root .. "/save.lua"
local restore_script = session_process_root .. "/restore.lua"
vim.fn.writefile({
	"local sessions = require('mayon.features.sessions')",
	"sessions.setup()",
	"vim.cmd.edit(vim.fn.fnameescape(" .. string.format("%q", process_file) .. "))",
	"assert(sessions.save(true), 'fresh process failed to save session')",
	"vim.cmd('qa!')",
}, save_script)
vim.fn.writefile({
	"local sessions = require('mayon.features.sessions')",
	"sessions.setup()",
	"local dashboard = vim.api.nvim_get_current_buf()",
	"vim.bo[dashboard].buftype = 'nofile'",
	"vim.bo[dashboard].buflisted = false",
	"vim.bo[dashboard].filetype = 'snacks_dashboard'",
	"assert(sessions.auto_restore(), 'fresh process did not find saved session')",
	"assert(vim.wait(500, function() return vim.api.nvim_get_current_buf() ~= dashboard and vim.api.nvim_buf_get_name(0) == "
		.. string.format("%q", process_file)
		.. " end), 'fresh process did not restore the project buffer')",
	"assert(not vim.api.nvim_buf_is_valid(dashboard), 'dashboard buffer survived session restore')",
	"assert(#vim.api.nvim_list_tabpages() == 1, 'restore created an extra tab')",
	"vim.cmd('qa!')",
}, restore_script)
local process_env = { HOME = process_home, XDG_STATE_HOME = process_state }
local saved = vim.system(vim.list_extend(vim.deepcopy(process_prefix), { "-l", save_script }), {
	cwd = process_project,
	env = process_env,
	text = true,
}):wait()
assert(saved.code == 0, "fresh session-save process failed: " .. (saved.stderr or saved.stdout or "unknown error"))
local restored = vim.system(vim.list_extend(vim.deepcopy(process_prefix), { "-l", restore_script }), {
	cwd = process_project,
	env = process_env,
	text = true,
}):wait()
assert(
	restored.code == 0,
	"fresh session-restore process failed: " .. (restored.stderr or restored.stdout or "unknown error")
)

-- Task discovery only inspects project metadata; it never executes a recipe.
local tasks_root = vim.fn.tempname()
vim.fn.mkdir(tasks_root, "p")
vim.fn.writefile({ ".PHONY: check clean", "check:", "clean:", "value: $(DEP)" }, tasks_root .. "/Makefile")
vim.fn.writefile({ '{"scripts":{"build":"echo build","test:unit":"echo test"}}' }, tasks_root .. "/package.json")
local tasks = require("mayon.features.tasks")
local discovered = tasks.discover(tasks_root)
local by_id = {}
for _, task in ipairs(discovered) do
	by_id[task.id] = task
end
assert(by_id["make:check"] and by_id["make:clean"], "Make targets were not discovered")
assert(by_id["npm:build"] and by_id["npm:test:unit"], "package scripts with colon names were not discovered")
assert(by_id["make:check"].cwd == tasks_root and by_id["npm:test:unit"].cwd == tasks_root)
assert(not by_id["make:value"], "Make dependency declaration was misread as a task")
assert(type(tasks.last) == "function" and type(tasks.run_last) == "function" and type(tasks.pick) == "function")
local snacks_module, launched = package.loaded.snacks, nil
package.loaded.snacks = {
	terminal = function(command, opts)
		launched = { command = command, opts = opts }
	end,
}
assert(tasks.run(by_id["npm:test:unit"]), "validated project task could not start")
package.loaded.snacks = snacks_module
assert(launched and launched.command == by_id["npm:test:unit"].command)
assert(launched.opts.cwd == tasks_root and launched.opts.win.position == "bottom")
assert(tasks.last().id == "npm:test:unit", "last task was not persisted for the toolbar")
assert(tasks.cached_last().id == "npm:test:unit", "toolbar cache did not update after a task run")
local discover = tasks.discover
tasks.discover = function()
	error("cached toolbar lookup must not rediscover tasks")
end
assert(tasks.cached_last().id == "npm:test:unit", "cached toolbar lookup depended on discovery")
tasks.discover = discover
package.loaded["mayon.features.tasks"] = nil
local restored_tasks = require("mayon.features.tasks")
assert(
	vim.wait(1000, function()
		return restored_tasks.cached_last() and restored_tasks.cached_last().id == "npm:test:unit"
	end),
	"cached task metadata was not restored asynchronously"
)
print("Filtered project sessions and metadata-only task discovery passed")
