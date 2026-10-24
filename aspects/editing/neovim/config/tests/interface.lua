-- Real optional-plugin setup, dashboard rendering, picker routing and folds.
vim.api.nvim_exec_autocmds("User", { pattern = "MayonVeryLazy" })
require("lz.n").trigger_load({ "codecompanion.nvim", "diffview.nvim", "grug-far.nvim", "trouble.nvim", "yazi.nvim" })
vim.wait(80)
assert(not vim.g.mayon_load_error, vim.g.mayon_load_error)
assert(package.loaded.codecompanion and package.loaded.diffview and package.loaded.noice)
local cc = require("codecompanion.config").config
assert(cc.interactions.chat.adapter == "deepseek")
assert(cc.interactions.cli.agents.codex.cmd == "codex" and cc.interactions.cli.agents.grok.cmd == "grok")
assert(cc.extensions.history.enabled)

local snacks = require("snacks")
vim.o.columns, vim.o.lines = 120, 45
local dashboard = snacks.dashboard.open({ win = 0, buf = 0 })
local lines = table.concat(vim.api.nvim_buf_get_lines(dashboard.buf, 0, -1, false), "\n")
assert(lines:find("M   M", 1, true) and lines:find("新建文件", 1, true), "dashboard header/keys did not render")
assert(lines:find("ms", 1, true), "dashboard lacks its config timing footer")
assert(vim.bo[dashboard.buf].filetype == "snacks_dashboard")

local real_picker = snacks.picker
local seen = {}
snacks.picker = setmetatable({}, {
	__index = function(_, source)
		return function()
			seen[source] = true
		end
	end,
})
for _, key in ipairs({ "ff", "fg", "fb", "fr", "fh", "f.", "fp", "fs", "fS", "fd", "fk", "f:", "f/", "g/", "gl", "gL" }) do
	local mapping = vim.fn.maparg(" " .. key, "n", false, true)
	assert(type(mapping.callback) == "function", "missing picker entry: " .. key)
	mapping.callback()
end
snacks.picker = real_picker
for _, source in ipairs({
	"files",
	"grep",
	"buffers",
	"recent",
	"help",
	"lines",
	"projects",
	"lsp_symbols",
	"lsp_workspace_symbols",
	"diagnostics",
	"keymaps",
	"command_history",
	"resume",
	"git_status",
	"git_log",
	"git_branches",
}) do
	assert(seen[source], source)
end
local picker = snacks.picker.files({ cwd = vim.env.NVIM_CONFIG_DIR, show_delay = 0 })
assert(
	vim.wait(2000, function()
		return #picker:items() > 0
	end),
	"file picker finder did not finish"
)
assert(#picker:items() > 0, "file picker found no config files")
picker:close()

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
vim.cmd.colorscheme("onedark-darker")
for _, group in ipairs({
	"MayonDashboardBlue",
	"MayonDashboardCyan",
	"OilDir",
	"NvimDapViewTabSelected",
	"RainbowDelimiterBlue",
	"InclineNormal",
	"SatelliteBar",
	"TinyInlineDiagnosticVirtualTextError",
	"TodoFgTODO",
	"OverseerRUNNING",
}) do
	local hl = vim.api.nvim_get_hl(0, { name = group, link = false })
	assert(next(hl), "missing theme group: " .. group)
end
assert(vim.v.errmsg == "", vim.v.errmsg)
print("Lazy setup, dashboard, unified pickers, folds and palette groups passed")
