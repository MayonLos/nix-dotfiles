-- Run with the wrapped editor and isolated XDG directories.
local ok, err = xpcall(function()
	assert(vim.v.errmsg == "", "startup error: " .. vim.v.errmsg)
	assert(vim.g.mayon_config_loaded, "entry point did not finish")
	assert(vim.g.colors_name == "onedark-darker")
	assert(vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg == 0x1f2329)
	assert(vim.wo.number and vim.wo.relativenumber and vim.wo.cursorline)
	assert(vim.wo.signcolumn == "yes")
	assert(vim.o.laststatus == 3 and vim.o.showtabline == 2)
	for _, provider in ipairs({ "python3", "ruby", "node", "perl" }) do
		assert(vim.g["loaded_" .. provider .. "_provider"] == 0)
	end
	for _, name in ipairs({
		"CodeCompanion",
		"CodeCompanionChat",
		"CodeCompanionCLI",
		"FzfLua",
		"GrugFar",
		"DiffviewOpen",
		"FormatDisable",
		"FormatEnable",
		"Urls",
		"UrlsBuffer",
		"ImagePreview",
	}) do
		assert(vim.fn.exists(":" .. name) == 2, "missing command: " .. name)
	end
	local blink = require("blink.cmp")
	local defaults = require("blink.cmp.config").sources.default
	assert(vim.deep_equal(defaults, { "lsp", "path", "snippets", "buffer" }))
	assert(blink.get_lsp_capabilities().textDocument.completion.completionItem.snippetSupport)
	assert(vim.tbl_count(require("mayon.lsp.servers").servers) == 16)
	assert(vim.lsp.config.lua_ls.capabilities.textDocument.completion.completionItem.snippetSupport)
	for _, lang in ipairs({ "lua", "nix", "javascript", "tsx", "cpp", "matlab", "latex" }) do
		assert(pcall(vim.treesitter.language.add, lang), "missing parser: " .. lang)
		assert(vim.treesitter.query.get(lang, "highlights"), "missing query: " .. lang)
	end
	-- The same init can be reached through wrapper VIMINIT and XDG init.lua.
	local before = #vim.api.nvim_get_autocmds({})
	dofile(vim.env.NVIM_CONFIG_DIR .. "/init.lua")
	assert(#vim.api.nvim_get_autocmds({}) == before, "entry ran twice")
	vim.cmd.colorscheme("onedark-darker")
	assert(
		vim.wait(1000, function()
			return vim.api.nvim_get_hl(0, { name = "MayonSLText", link = false }).fg ~= nil
		end),
		"statusline palette did not refresh"
	)
	assert(vim.api.nvim_get_hl(0, { name = "Normal", link = false }).bg == 0x1f2329)
	assert(vim.api.nvim_get_hl(0, { name = "MayonUIFloat", link = false }).bg == 0x181b20)
	assert(vim.api.nvim_get_hl(0, { name = "TreesitterContext", link = false }).bg == 0x181b20)
	assert(vim.api.nvim_get_hl(0, { name = "MayonSLText", link = false }).fg)
	assert(vim.api.nvim_get_hl(0, { name = "BlinkCmpMenu", link = false }).bg == 0x181b20)
	local urls = require("mayon.features.urls")
	local scanned = urls.scan("- [ ] [中文](https://example.com/a)，说明")
	assert(#scanned == 1 and scanned[1].url == "https://example.com/a" and scanned[1].title == "中文")
	-- Retain keyword-aware boolean toggling, without matching identifiers.
	local toggle = vim.fn.maparg("<leader>ub", "n", false, true).callback
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "true false true_value" })
	vim.api.nvim_win_set_cursor(0, { 1, 1 })
	toggle()
	assert(vim.api.nvim_get_current_line() == "false false true_value")
	vim.api.nvim_win_set_cursor(0, { 1, 14 })
	toggle()
	assert(vim.api.nvim_get_current_line() == "false false true_value")
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "" })
	vim.bo.modified = false
	assert(vim.v.errmsg == "", vim.v.errmsg)
end, debug.traceback)
if not ok then
	io.stderr:write(err .. "\n")
	vim.cmd("cquit 1")
end
io.stdout:write("wrapped Neovim startup and migration checks passed\n")
vim.cmd("qa!")
