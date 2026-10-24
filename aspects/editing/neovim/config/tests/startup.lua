-- Run the complete production configuration with real Nix-pinned plugins.
assert(vim.v.errmsg == "", vim.v.errmsg)
assert(vim.g.mayon_config_loaded)
assert(vim.g.colors_name == "onedark-darker")
assert(vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg == 0x1f2329)
assert(vim.wo.number and vim.wo.relativenumber and vim.wo.cursorline and vim.wo.wrap)
assert(vim.o.laststatus == 3 and vim.o.showtabline == 2)
for _, provider in ipairs({ "python3", "ruby", "node", "perl" }) do
	assert(vim.g["loaded_" .. provider .. "_provider"] == 0)
end
for _, name in ipairs({
	"CodeCompanion",
	"CodeCompanionChat",
	"CodeCompanionCLI",
	"Oil",
	"GrugFar",
	"DiffviewOpen",
	"Trouble",
	"Urls",
	"UrlsBuffer",
	"ImagePreview",
}) do
	assert(vim.fn.exists(":" .. name) == 2, "missing command: " .. name)
end
for _, module in ipairs({ "codecompanion", "diffview", "lazydev", "noice", "oil", "dap", "overseer" }) do
	assert(not package.loaded[module], module .. " was eagerly loaded")
end
assert(vim.fn.exists(":FzfLua") == 0 and not package.loaded.ufo)
vim.api.nvim_exec_autocmds("BufReadPre", {})
require("lz.n").trigger_load("nvim-treesitter")
local blink = require("blink.cmp")
assert(vim.deep_equal(require("blink.cmp.config").sources.default, { "lsp", "path", "snippets", "buffer" }))
assert(blink.get_lsp_capabilities().textDocument.completion.completionItem.snippetSupport)
local selection = require("blink.cmp.config").completion.list.selection
-- Blink wraps mode-specific values in functions during setup.
local function value(option)
	if type(option) == "function" then
		return option({})
	end
	return option
end
assert(value(selection.preselect) == false and value(selection.auto_insert) == false)
assert(vim.tbl_count(require("mayon.lsp.servers").servers) == 16)
for _, lang in ipairs({ "lua", "nix", "javascript", "tsx", "cpp", "matlab", "latex", "markdown", "markdown_inline" }) do
	assert(pcall(vim.treesitter.language.add, lang), "missing parser: " .. lang)
end
local before = #vim.api.nvim_get_autocmds({})
dofile(vim.env.NVIM_CONFIG_DIR .. "/init.lua")
assert(#vim.api.nvim_get_autocmds({}) == before, "configuration loaded twice")
local snacks = require("snacks")
assert(snacks.config.explorer.enabled and snacks.config.notifier.enabled)
assert(snacks.config.dashboard.enabled)
assert(not vim.tbl_contains(snacks.config.image.formats, "pdf"), "PDF has two owners")
local db = require("snacks.picker.util.db")
local sqlite = db.new(vim.fn.tempname() .. ".sqlite3", "string")
sqlite:set("fixture", "known value")
assert(sqlite:get("fixture") == "known value")
sqlite:close()
local urls = require("mayon.features.urls").scan("[中文](https://example.com/a)，说明")
assert(#urls == 1 and urls[1].url == "https://example.com/a")
assert(vim.v.errmsg == "", vim.v.errmsg)
print("Production editor, real plugins, SQLite and single entry point passed")
