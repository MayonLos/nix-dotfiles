-- Run the complete production configuration with real Nix-pinned plugins.
assert(vim.v.errmsg == "", vim.v.errmsg)
assert(vim.g.mayon_config_loaded)
assert(vim.g.colors_name == "onedark")
local palette = require("mayon.generated").palette
assert(vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg == tonumber(palette.deep:sub(2), 16))
assert(vim.api.nvim_get_hl(0, { name = "Normal", link = false }).fg == tonumber(palette.brightFg:sub(2), 16))
assert(vim.api.nvim_get_hl(0, { name = "NormalFloat", link = false }).bg == tonumber(palette.deep:sub(2), 16))
assert(vim.api.nvim_get_hl(0, { name = "Pmenu", link = false }).bg == tonumber(palette.deep:sub(2), 16))
assert(vim.api.nvim_get_hl(0, { name = "PmenuSel", link = false }).bg == tonumber(palette.selection:sub(2), 16))
for _, name in ipairs({ "DiffAdd", "DiffChange", "DiffText", "DiffDelete" }) do
	local highlight = vim.api.nvim_get_hl(0, { name = name, link = false })
	assert(highlight.bg and highlight.fg == tonumber(palette.brightFg:sub(2), 16), "invalid diff highlight: " .. name)
end
assert(vim.api.nvim_get_hl(0, { name = "Visual", link = false }).fg == tonumber(palette.brightFg:sub(2), 16))
assert(vim.api.nvim_get_hl(0, { name = "Visual", link = false }).bg == tonumber(palette.selection:sub(2), 16))
assert(vim.api.nvim_get_hl(0, { name = "LineNr", link = false }).fg == tonumber(palette.fg:sub(2), 16))
assert(vim.api.nvim_get_hl(0, { name = "@keyword.function", link = false }).fg == tonumber(palette.cyan:sub(2), 16))
assert(vim.wo.number and vim.wo.relativenumber and vim.wo.cursorline and vim.wo.wrap)
assert(vim.o.laststatus == 3 and vim.o.showtabline == 2)
for _, provider in ipairs({ "python3", "ruby", "node", "perl" }) do
	assert(vim.g["loaded_" .. provider .. "_provider"] == 0)
end
for _, name in ipairs({
	"CodeCompanion",
	"CodeCompanionChat",
	"Oil",
	"GrugFar",
	"CodeDiff",
	"Trouble",
	"Urls",
	"UrlsBuffer",
	"ImagePreview",
}) do
	assert(vim.fn.exists(":" .. name) == 2, "missing command: " .. name)
end
for _, module in ipairs({
	"codecompanion",
	"codediff",
	"lazydev",
	"oil",
	"claudecode",
	"sidekick",
	"copilot",
	"minuet",
	"edgy",
	"smart-splits",
}) do
	assert(not package.loaded[module], module .. " was eagerly loaded")
end
for _, module in ipairs({
	"vim.lsp",
	"snacks.explorer.actions",
	"snacks.explorer.tree",
	"snacks.git",
	"nvim-web-devicons",
	"mayon.features.sessions",
	"mayon.features.urls",
	"mayon.features.fileops",
	"mayon.ui.dashboard",
	"snacks.dashboard",
}) do
	assert(not package.loaded[module], module .. " was eagerly loaded")
end
assert(vim.fn.exists(":FzfLua") == 0 and not package.loaded.ufo)
-- A special UI FileType must not initialize language services.
vim.bo.buftype = "nofile"
vim.bo.filetype = "snacks_dashboard"
assert(not package.loaded["vim.lsp"], "dashboard FileType must not initialize LSP")
vim.bo.filetype = ""
vim.bo.buftype = ""
-- Restore through the initially lazy mapping, before any file has been read.
local session_dir = vim.fn.stdpath("state") .. "/sessions"
vim.fn.mkdir(session_dir, "p")
local session_fixture = session_dir .. "/lazy-restore.vim"
vim.fn.writefile({ "let g:mayon_lazy_session_restored = 1" }, session_fixture)
vim.fn.maparg("<leader>pl", "n", false, true).callback()
assert(vim.g.mayon_lazy_session_restored == 1, "lazy session mapping did not restore the last session")
assert(package.loaded["mayon.features.sessions"], "session implementation must load at the restore entry point")
vim.fn.delete(session_fixture)
vim.bo.filetype = "text"
assert(package.loaded["vim.lsp"], "LSP core should load on the first FileType")
require("lz.n").trigger_load("nvim-treesitter")
assert(not package.loaded["blink.cmp"] and not package.loaded.copilot)
assert(vim.opt.completeopt:get() and vim.tbl_contains(vim.opt.completeopt:get(), "noselect"))
assert(package.loaded["vim._core.ui2"])
assert(vim.tbl_count(require("mayon.lsp.servers").servers) == 17)
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
