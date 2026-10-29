-- Project sessions retain ordinary file splits but omit tool-only tabs and
-- panes. Saving must leave the live tool UI and buffer flags untouched.
local sessions = require("mayon.features.sessions")
sessions.setup()

local root = vim.fn.tempname() .. "/session-tools"
vim.fn.mkdir(root, "p")
local first_path, second_path, third_path = root .. "/first.lua", root .. "/second.lua", root .. "/third.lua"
vim.fn.writefile({ "local function first_document() return true end" }, first_path)
vim.fn.writefile({ "local function second_document() return true end" }, second_path)
vim.fn.writefile({ "local function third_document() return true end" }, third_path)
vim.cmd.lcd(vim.fn.fnameescape(root))
vim.cmd.edit(vim.fn.fnameescape(first_path))
local project_tab = vim.api.nvim_get_current_tabpage()
vim.cmd("vsplit " .. vim.fn.fnameescape(second_path))

vim.cmd("vsplit")
local tree_win = vim.api.nvim_get_current_win()
local tree_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_win_set_buf(tree_win, tree_buf)
vim.bo[tree_buf].buftype = "nofile"
vim.bo[tree_buf].bufhidden = "wipe"
vim.bo[tree_buf].filetype = "snacks_picker_list"
vim.bo[tree_buf].buflisted = true
vim.api.nvim_buf_set_name(tree_buf, "SessionToolsTreeFixture")

vim.cmd("tabnew")
local tool_tab = vim.api.nvim_get_current_tabpage()
local tool_buf = vim.api.nvim_get_current_buf()
vim.bo[tool_buf].buftype = "nofile"
vim.bo[tool_buf].bufhidden = "wipe"
vim.bo[tool_buf].filetype = "snacks_dashboard"
vim.bo[tool_buf].buflisted = true
vim.api.nvim_buf_set_name(tool_buf, "SessionToolsOnlyTabFixture")
vim.cmd("tabnew " .. vim.fn.fnameescape(third_path))
assert(#vim.api.nvim_list_tabpages() == 3, "fixture must contain code tabs around a tool-only tab")
assert(vim.api.nvim_tabpage_get_number(tool_tab) == 2, "tool-only tab must sit between code tabs")
assert(#vim.api.nvim_tabpage_list_wins(project_tab) == 3, "fixture must contain two code panes and a tree pane")

local function snapshot()
	local result = {
		tabs = vim.api.nvim_list_tabpages(),
		current_tab = vim.api.nvim_get_current_tabpage(),
		current_win = vim.api.nvim_get_current_win(),
		windows = {},
	}
	for _, tabpage in ipairs(result.tabs) do
		result.windows[tabpage] = {}
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
			result.windows[tabpage][#result.windows[tabpage] + 1] = {
				id = win,
				buf = vim.api.nvim_win_get_buf(win),
				width = vim.api.nvim_win_get_width(win),
				height = vim.api.nvim_win_get_height(win),
			}
		end
	end
	return result
end

local function assert_snapshot(expected, message)
	local actual = snapshot()
	assert(vim.deep_equal(actual.tabs, expected.tabs), message .. ": tab pages changed")
	assert(
		actual.current_tab == expected.current_tab and actual.current_win == expected.current_win,
		message .. ": focus changed"
	)
	for tabpage, windows in pairs(expected.windows) do
		assert(vim.deep_equal(actual.windows[tabpage], windows), message .. ": windows or buffer assignments changed")
	end
end

local before_save = snapshot()
local tree_listed = vim.bo[tree_buf].buflisted
local tool_listed = vim.bo[tool_buf].buflisted
assert(sessions.save(true), "session writer should save the project tab")
assert_snapshot(before_save, "session save")
assert(vim.bo[tree_buf].buflisted == tree_listed, "saving changed the tree buffer's listed state")
assert(vim.bo[tool_buf].buflisted == tool_listed, "saving changed the tool tab's listed state")
assert(vim.api.nvim_buf_is_valid(tree_buf), "session save destroyed the live tree buffer")

local content = table.concat(vim.fn.readfile(sessions.path()), "\n")
assert(
	content:find("first.lua", 1, true) and content:find("second.lua", 1, true) and content:find("third.lua", 1, true),
	"ordinary code splits and tabs were not saved"
)
assert(not content:find("SessionToolsTreeFixture", 1, true), "tree buffer leaked into the saved session")
assert(not content:find("SessionToolsOnlyTabFixture", 1, true), "tool-only tab leaked into the saved session")

-- The save guard must leave user edits intact and must not alter the layout.
local first_buf = vim.fn.bufnr(first_path)
vim.api.nvim_buf_set_lines(first_buf, 0, -1, false, { "modified fixture" })
local before_skip = snapshot()
assert(not sessions.save(true), "modified buffers must prevent session writes")
assert(vim.bo[first_buf].modified, "session save cleared a modified buffer")
assert_snapshot(before_skip, "skipped session save")
vim.bo[first_buf].modified = false
vim.api.nvim_buf_set_lines(first_buf, 0, -1, false, { "local function first_document() return true end" })
vim.bo[first_buf].modified = false

sessions.load()
assert(
	vim.wait(300, function()
		return #vim.api.nvim_list_tabpages() == 2 and #vim.api.nvim_tabpage_list_wins(0) == 1
	end),
	"restore must keep the ordinary code tabs and split while removing the tool-only tab/pane"
)
local restored_files = {}
local restored_windows = 0
for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
		local buf = vim.api.nvim_win_get_buf(win)
		local name = vim.api.nvim_buf_get_name(buf)
		assert(vim.bo[buf].buftype == "", "restore left a tool-only window")
		restored_files[name] = true
		restored_windows = restored_windows + 1
	end
end
assert(restored_windows == 3, "restore changed the ordinary document window count")
assert(
	restored_files[first_path] and restored_files[second_path] and restored_files[third_path],
	"restore lost an ordinary project split or tab"
)
print("Project session tool filtering and live-layout preservation passed")

-- A pre-fix native session still contains the blank tool-tab placeholder.
-- Loading it must repair only the live layout and leave those bytes intact.
vim.cmd.tabnew()
vim.bo.buftype = "nofile"
vim.bo.bufhidden = "wipe"
vim.bo.filetype = "snacks_dashboard"
vim.cmd("mksession! " .. vim.fn.fnameescape(sessions.path()))
local legacy = vim.fn.readfile(sessions.path())
assert(#vim.api.nvim_list_tabpages() == 3)
sessions.load()
assert(#vim.api.nvim_list_tabpages() == 2, "legacy session restored an empty tool tab")
assert(vim.deep_equal(vim.fn.readfile(sessions.path()), legacy), "loading rewrote the legacy session file")
print("Legacy session live-layout cleanup passed")

-- SessionLoadPost integrations may legitimately open unmodified tool content.
-- That content is not an empty native placeholder and must survive cleanup.
local preserved_tool
vim.api.nvim_create_autocmd("SessionLoadPost", {
	once = true,
	callback = function()
		vim.cmd.tabnew()
		preserved_tool = vim.api.nvim_get_current_buf()
		vim.bo.buftype = "nofile"
		vim.bo.bufhidden = "wipe"
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { "valuable temporary tool content" })
		vim.bo.modified = false
	end,
})
sessions.load()
assert(preserved_tool and vim.api.nvim_buf_is_valid(preserved_tool), "restore discarded plugin-owned tool content")
assert(vim.api.nvim_buf_get_lines(preserved_tool, 0, 1, false)[1] == "valuable temporary tool content")
assert(#vim.api.nvim_list_tabpages() == 3, "restore must retain file tabs and the populated tool tab")
print("SessionLoadPost tool-content preservation passed")
