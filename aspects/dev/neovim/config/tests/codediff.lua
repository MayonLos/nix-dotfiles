local git_specs = require("mayon.plugins.git")
vim.g.mapleader = " "
require("lz.n").trigger_load("gitsigns.nvim")

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
	CodeDiffLineInsert = { fg = palette.brightFg, bg = blend(palette.green, palette.deep, 0.08) },
	CodeDiffLineDelete = { fg = palette.brightFg, bg = blend(palette.red, palette.deep, 0.08) },
	CodeDiffCharInsert = { fg = palette.brightFg, bg = blend(palette.green, palette.deep, 0.12) },
	CodeDiffCharDelete = { fg = palette.brightFg, bg = blend(palette.red, palette.deep, 0.12) },
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
end

local repo = vim.fn.tempname()
vim.fn.mkdir(repo, "p")
git({ "init", "-q" }, repo)
git({ "config", "user.name", "Codediff Test" }, repo)
git({ "config", "user.email", "codediff@example.invalid" }, repo)
vim.fn.writefile({ "before", "same" }, repo .. "/review.txt")
git({ "add", "review.txt" }, repo)
git({ "commit", "-qm", "fixture" }, repo)
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
assert_diff_highlights()

-- codediff's ColorScheme hook resets the foregrounds after the theme hook;
-- the post-plugin listener must restore all four palette-backed groups.
vim.cmd.colorscheme("onedark")
assert_diff_highlights()

vim.api.nvim_del_augroup_by_id(group)
vim.cmd("tabonly!")
vim.fn.delete(repo, "rf")
print("CodeDiff setup, mappings, packaged native library, and temporary Git review passed")
