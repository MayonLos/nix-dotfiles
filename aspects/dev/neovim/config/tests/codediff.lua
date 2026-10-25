local git_specs = require("mayon.plugins.git")
vim.g.mapleader = " "
require("lz.n").trigger_load("gitsigns.nvim")
assert(
	vim.wait(1000, function()
		return vim.fn.maparg(" gb", "n") ~= ""
	end),
	"gitsigns setup did not install its mappings"
)

local gitsigns = require("gitsigns")
local git_config = require("gitsigns.config").config
assert(
	git_config.signs.add.text == "▎" and git_config.signs.change.text == "▎",
	vim.inspect({ add = git_config.signs.add, change = git_config.signs.change })
)
assert(git_config.signs.delete.text == "▎" and git_config.signs.topdelete.text == "▎")
assert(git_config.current_line_blame == false, "Git blame must start disabled")
local blame_toggle = vim.fn.maparg(" gb", "n", false, true)
assert(blame_toggle.callback and blame_toggle.desc == "切换当前行 Git blame", "<leader>gb must toggle blame")
local blame_toggles = 0
local toggle_blame = gitsigns.toggle_current_line_blame
gitsigns.toggle_current_line_blame = function()
	blame_toggles = blame_toggles + 1
end
blame_toggle.callback()
gitsigns.toggle_current_line_blame = toggle_blame
assert(blame_toggles == 1, "<leader>gb did not call the blame toggle")

for _, spec in ipairs({
	{ "<leader>gd", "审阅工作区 Git 改动" },
	{ "<leader>gf", "查看当前文件历史" },
	{ "<leader>gD", "与提交或分支比较" },
	{ "<leader>gC", "打开当前文件冲突审阅" },
	{ "<leader>gT", "比较两个目录（Neovim 原生）" },
}) do
	local lhs = spec[1]:gsub("<leader>", vim.g.mapleader)
	local mapping = vim.fn.maparg(lhs, "n", false, true)
	assert(mapping.callback or mapping.rhs ~= "", "missing Git review mapping: " .. spec[1])
	assert(mapping.desc == spec[2], "unexpected Git review mapping description: " .. spec[1])
end

local plugin_spec = assert(git_specs[2], "codediff plugin spec missing")
require("lz.n").trigger_load("codediff.nvim")
local codediff = require("codediff.config").options
assert(codediff.diff.layout == "side-by-side")
assert(codediff.explorer.position == "left" and codediff.explorer.width == 30)
assert(codediff.explorer.view_mode == "tree")
local palette = require("mayon.generated").palette
local blend = require("mayon.ui.theme").blend
local expected_highlights = {
	CodeDiffLineInsert = { fg = palette.brightFg, bg = blend(palette.green, palette.bg, 0.12) },
	CodeDiffLineDelete = { fg = palette.brightFg, bg = blend(palette.red, palette.bg, 0.12) },
	CodeDiffCharInsert = { fg = palette.brightFg, bg = blend(palette.green, palette.bg, 0.18) },
	CodeDiffCharDelete = { fg = palette.brightFg, bg = blend(palette.red, palette.bg, 0.18) },
}
assert(codediff.highlights.line_insert == expected_highlights.CodeDiffLineInsert.bg)
assert(codediff.highlights.line_delete == expected_highlights.CodeDiffLineDelete.bg)
assert(codediff.highlights.char_insert == expected_highlights.CodeDiffCharInsert.bg)
assert(codediff.highlights.char_delete == expected_highlights.CodeDiffCharDelete.bg)

local function assert_diff_highlights()
	for name, expected in pairs(expected_highlights) do
		local actual = vim.api.nvim_get_hl(0, { name = name, link = false })
		assert(actual.fg == tonumber(expected.fg:sub(2), 16), name .. " foreground differs from palette brightFg")
		assert(actual.bg == tonumber(expected.bg:sub(2), 16), name .. " background differs from palette blend")
	end
end
assert_diff_highlights()
assert(vim.env.VSCODE_DIFF_NO_AUTO_INSTALL == "1", "Nix package auto-installer must be disabled")
local package_root = require("codediff.core.path").get_plugin_root()
assert(vim.fn.filereadable(package_root .. "/libvscode_diff.so") == 1, "Nix package lacks libvscode_diff.so")

local function git(args, cwd)
	local result = vim.system(vim.list_extend({ "git", "-C", cwd }, args), { text = true }):wait()
	assert(result.code == 0, result.stderr)
	return vim.trim(result.stdout)
end

local repo = vim.fn.tempname()
vim.fn.mkdir(repo, "p")
git({ "init", "--initial-branch=main", "-q" }, repo)
local blob_result = vim.system(
	{ "git", "-C", repo, "hash-object", "-w", "--stdin" },
	{ text = true, stdin = "before\nsame\n" }
)
	:wait()
assert(blob_result.code == 0, blob_result.stderr)
local tree_result = vim.system(
	{ "git", "-C", repo, "mktree" },
	{ text = true, stdin = "100644 blob " .. vim.trim(blob_result.stdout) .. "\treview.txt\n" }
):wait()
assert(tree_result.code == 0, tree_result.stderr)
local commit_result = vim.system({ "git", "-C", repo, "commit-tree", vim.trim(tree_result.stdout), "-m", "fixture" }, {
	text = true,
	env = {
		GIT_AUTHOR_NAME = "CodeDiff Test",
		GIT_AUTHOR_EMAIL = "codediff@example.invalid",
		GIT_COMMITTER_NAME = "CodeDiff Test",
		GIT_COMMITTER_EMAIL = "codediff@example.invalid",
	},
})
local commit = commit_result:wait()
assert(commit.code == 0, commit.stderr)
git({ "update-ref", "refs/heads/main", vim.trim(commit.stdout) }, repo)
git({ "update-index", "--add", "--cacheinfo", "100644," .. vim.trim(blob_result.stdout) .. ",review.txt" }, repo)
vim.fn.writefile({ "before", "same" }, repo .. "/review.txt")
vim.fn.writefile({ "after", "same" }, repo .. "/review.txt")

local opened
local group = vim.api.nvim_create_augroup("MayonCodediffSmoke", { clear = true })
vim.api.nvim_create_autocmd("User", {
	group = group,
	pattern = "CodeDiffOpen",
	callback = function(event)
		if event.data and event.data.mode == "explorer" then
			opened = event.data
		end
	end,
})
vim.cmd.lcd(repo)
vim.cmd("CodeDiff")
assert(
	vim.wait(5000, function()
		return opened ~= nil
	end),
	"CodeDiff did not open the temporary repository review explorer"
)
assert(vim.api.nvim_tabpage_is_valid(opened.tabpage), "CodeDiff explorer tab is invalid")
-- CodeDiffOpen announces the tab before its asynchronous file-selection
-- update has loaded/rendered both buffers. Keep the fixture/cwd alive until
-- the actual diff is ready, rather than deleting it underneath scheduled work.
local lifecycle = require("codediff.ui.lifecycle")
assert(
	vim.wait(5000, function()
		local original, modified = lifecycle.get_buffers(opened.tabpage)
		if type(original) ~= "number" or type(modified) ~= "number" then
			return false
		end
		if not vim.api.nvim_buf_is_loaded(original) or not vim.api.nvim_buf_is_loaded(modified) then
			return false
		end
		return vim.api.nvim_buf_get_lines(original, 0, -1, false)[1] == "before"
			and vim.api.nvim_buf_get_lines(modified, 0, -1, false)[1] == "after"
	end),
	"CodeDiff did not load both sides of the temporary review"
)
vim.wait(50)
assert_diff_highlights()

-- codediff's ColorScheme hook resets the foregrounds after the theme hook;
-- the post-plugin listener must restore all four palette-backed groups.
vim.cmd.colorscheme("onedark")
assert_diff_highlights()

vim.api.nvim_del_augroup_by_id(group)
vim.cmd("tabonly!")
vim.wait(50)
vim.cmd.lcd(vim.fn.fnamemodify(repo, ":h"))
vim.fn.delete(repo, "rf")
assert(vim.v.errmsg == "", vim.v.errmsg)
print("CodeDiff setup, mappings, packaged native library, and temporary Git review passed")
