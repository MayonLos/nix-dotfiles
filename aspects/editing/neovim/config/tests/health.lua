vim.api.nvim_exec_autocmds("UIEnter", {})
vim.api.nvim_exec_autocmds("BufReadPre", {})
require("lz.n").trigger_load("nvim-treesitter")
vim.api.nvim_exec_autocmds("User", { pattern = "MayonVeryLazy" })
require("lz.n").trigger_load({
	"codecompanion.nvim",
	"claudecode.nvim",
	"sidekick.nvim",
	"minuet-ai.nvim",
	"edgy.nvim",
	"smart-splits.nvim",
	"codediff.nvim",
	"grug-far.nvim",
	"trouble.nvim",
	"yazi.nvim",
	"oil.nvim",
})
vim.wait(100)
assert(not vim.g.mayon_load_error, vim.g.mayon_load_error)
vim.cmd.checkhealth()
vim.wait(1000)
local report = vim.api.nvim_buf_get_lines(0, 0, -1, false)
vim.fn.writefile(report, assert(vim.env.NVIM_HEALTH_REPORT))
local errors, warnings = 0, 0
for _, line in ipairs(report) do
	if line:find("ERROR", 1, true) then
		errors = errors + 1
		print(line)
	end
	if line:find("WARNING", 1, true) then
		warnings = warnings + 1
	end
end
print(("checkhealth: %d ERROR, %d WARNING"):format(errors, warnings))
