-- Project sessions are named per cwd + git branch and restored without
-- AI/tool windows. A programmatic save leaves the live layout alone, restore
-- drops tool-only tabs, keeps terminals and unlisted AI buffers alive, and the
-- document layout survives a save/load cycle.
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
vim.cmd("vsplit " .. vim.fn.fnameescape(second_path))

-- A tool-only tab that must not survive into the saved session.
vim.cmd("tabnew")
local tool_buf = vim.api.nvim_get_current_buf()
vim.bo[tool_buf].buftype = "nofile"
vim.bo[tool_buf].bufhidden = "wipe"
vim.bo[tool_buf].filetype = "claudecode"
vim.bo[tool_buf].buflisted = true
vim.api.nvim_buf_set_name(tool_buf, "SessionToolsToolFixture")
vim.cmd("tabnew " .. vim.fn.fnameescape(third_path))
assert(#vim.api.nvim_list_tabpages() == 3, "fixture must contain two document tabs around a tool tab")

assert(sessions.save(true), "session writer should save the document tabs")
-- Saving must not change the user's layout.
assert(#vim.api.nvim_list_tabpages() == 3, "programmatic save changed the live tab layout")

-- The saved session contains only the document files.
local content = table.concat(vim.fn.readfile(sessions.path()), "\n")
assert(content:find("first.lua", 1, true) and content:find("second.lua", 1, true), "document splits were not saved")
assert(content:find("third.lua", 1, true), "document tab was not saved")
assert(not content:find("SessionToolsToolFixture", 1, true), "tool buffer leaked into the saved session")

-- A modified buffer must prevent a write.
local first_buf = vim.fn.bufnr(first_path)
vim.api.nvim_buf_set_lines(first_buf, 0, -1, false, { "modified fixture" })
assert(not sessions.save(true), "modified buffers must prevent session writes")
assert(vim.bo[first_buf].modified, "session save cleared a modified buffer")
vim.bo[first_buf].modified = false
vim.api.nvim_buf_set_lines(first_buf, 0, -1, false, { "local function first_document() return true end" })
vim.bo[first_buf].modified = false

-- Running terminals and unlisted AI buffers must survive a manual load.
local term_buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_call(term_buf, function()
	vim.fn.jobstart({ "sh", "-c", "sleep 30" }, { term = true })
end)
local ai_buf = vim.api.nvim_create_buf(false, true)
vim.bo[ai_buf].filetype = "codecompanion"
vim.api.nvim_buf_set_lines(ai_buf, 0, -1, false, { "conversation" })

assert(sessions.load(), "session load should restore the saved project")
assert(vim.api.nvim_buf_is_valid(term_buf), "session load wiped a running terminal")
assert(vim.bo[term_buf].buftype == "terminal", "session load replaced the terminal buffer")
assert(vim.api.nvim_buf_is_valid(ai_buf), "session load wiped an unlisted AI buffer")
assert(vim.api.nvim_buf_get_lines(ai_buf, 0, 1, false)[1] == "conversation", "AI buffer content was lost")
assert(
	vim.wait(300, function()
		local windows = 0
		for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
			windows = windows + #vim.api.nvim_tabpage_list_wins(tabpage)
		end
		return #vim.api.nvim_list_tabpages() == 2 and windows == 3
	end),
	"restore must keep the document tabs and split"
)
local restored_files = {}
local restored_windows = 0
for _, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
		local buf = vim.api.nvim_win_get_buf(win)
		local name = vim.api.nvim_buf_get_name(buf)
		assert(vim.bo[buf].buftype == "", "restore left a tool window")
		restored_files[name] = true
		restored_windows = restored_windows + 1
	end
end
assert(restored_windows == 3, "restore changed the ordinary document window count")
assert(
	restored_files[first_path] and restored_files[second_path] and restored_files[third_path],
	"restore lost an ordinary project split or tab"
)
print("Project session save/load and tool filtering passed")

-- The disable/auto_restore entry points stay available and behave.
assert(type(sessions.last) == "function" and type(sessions.disable) == "function")
assert(type(sessions.auto_restore) == "function" and type(sessions.setup) == "function")
print("Session public entry points passed")

-- Branch is part of the session name; the cache is reused until DirChanged.
local repo = root .. "/branch-repo"
vim.fn.mkdir(repo, "p")
assert(vim.system({ "git", "init", "--initial-branch=main", "-q", repo }):wait().code == 0, "git init failed")
vim.cmd.lcd(vim.fn.fnameescape(repo))
vim.api.nvim_exec_autocmds("DirChanged", { pattern = "dir" })
local main_session = sessions.path()
assert(
	vim.system({ "git", "-C", repo, "checkout", "-q", "-b", "feature" }):wait().code == 0,
	"git branch fixture failed"
)
assert(sessions.path() == main_session, "branch lookup should be cached between DirChanged events")
vim.api.nvim_exec_autocmds("DirChanged", { pattern = "dir" })
assert(sessions.path() ~= main_session, "DirChanged should invalidate the cached git branch")
print("Session branch naming and cache invalidation passed")

-- Fallbacks: a feature branch without its own session uses the branch-less
-- (main) session; a legacy '%'-encoded file is still read.
local fallback_file = repo .. "/fallback.lua"
vim.fn.writefile({ "return 'fallback'" }, fallback_file)
vim.cmd("silent only")
vim.cmd("silent tabonly")
vim.cmd.edit(vim.fn.fnameescape(fallback_file))
-- The fixture repo has no commits; switch the unborn branch via HEAD.
assert(vim.system({ "git", "-C", repo, "symbolic-ref", "HEAD", "refs/heads/main" }):wait().code == 0)
vim.api.nvim_exec_autocmds("FocusGained", {})
assert(sessions.path() == main_session, "FocusGained should invalidate the cached git branch")
assert(sessions.save(true), "main session save failed")
assert(vim.system({ "git", "-C", repo, "symbolic-ref", "HEAD", "refs/heads/feature" }):wait().code == 0)
vim.api.nvim_exec_autocmds("TermLeave", {})
assert(sessions.path() ~= main_session, "TermLeave should invalidate the cached git branch")
assert(vim.fn.filereadable(sessions.path()) == 0, "fixture: feature session must not exist")
vim.cmd.enew()
assert(sessions.load(), "feature branch did not fall back to the main session")
assert(vim.api.nvim_buf_get_name(0) == fallback_file, "main-session fallback restored the wrong file")

local session_dir = vim.fn.stdpath("state") .. "/sessions"
vim.fn.rename(main_session, session_dir .. "/" .. repo:gsub("[\\/:]+", "%%") .. ".vim")
vim.cmd.enew()
assert(sessions.load(), "legacy session file was not restored")
assert(vim.api.nvim_buf_get_name(0) == fallback_file, "legacy session restored the wrong file")
print("Session branch and legacy fallbacks passed")

-- last() only considers *.vim files in the session directory.
vim.fn.writefile({ "echoerr 'leftover'" }, session_dir .. "/stale.vim.tmp.1.2")
vim.fn.writefile({ "echoerr 'local'" }, repo .. "/Session.vim")
vim.cmd.enew()
assert(sessions.last(), "last() should restore the newest session file")
assert(vim.v.this_session:match("%.vim$"), "last() picked a non-session file")
assert(vim.fs.dirname(vim.v.this_session) == session_dir, "last() picked a file outside the session directory")
print("Latest session lookup passed")
