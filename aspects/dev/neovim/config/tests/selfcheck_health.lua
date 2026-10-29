local capture = assert(_G.MayonSelfcheck)
capture.hook_notify()
capture.phase = "health setup"
vim.api.nvim_exec_autocmds("UIEnter", {})
vim.api.nvim_exec_autocmds("User", { pattern = "MayonVeryLazy" })
vim.bo.filetype = "text"
vim.api.nvim_exec_autocmds("BufReadPre", {})
require("mayon.features.ai_completion").set("off")
for _, domain in ipairs({
	"completion",
	"languages",
	"lua",
	"treesitter",
	"editing",
	"formatting",
	"lint",
	"git",
	"navigation",
	"utility",
	"markdown",
	"ai",
	"decorations",
	"layout",
}) do
	for _, spec in ipairs(require("mayon.plugins." .. domain)) do
		if spec.enabled ~= false then
			require("lz.n").trigger_load(spec[1])
		end
	end
end
vim.wait(500)
capture.hook_notify()
capture.phase = "checkhealth"
vim.cmd.checkhealth()
vim.wait(1000)
local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
vim.fn.writefile(lines, assert(vim.env.NVIM_HEALTH_REPORT))
if #vim.api.nvim_list_uis() > 0 then
	for _, line in ipairs(lines) do
		assert(not line:find("❌ ERROR", 1, true), "checkhealth ERROR: " .. line)
	end
end
