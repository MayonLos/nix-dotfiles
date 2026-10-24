local M = {}
function M.setup()
	local started = vim.uv.hrtime()
	require("mayon.config.options").setup()
	require("vim._core.ui2").enable()
	require("mayon.ui.theme").setup()
	require("mayon.ui.icons").setup()
	require("mayon.config.loader").setup()
	require("mayon.features.fileops").setup()
	require("mayon.features.sessions").setup()
	require("mayon.features.urls").setup()
	require("mayon.features.scratch").setup()
	-- Formula handling is only initialized in relevant documents.
	vim.api.nvim_create_autocmd("FileType", {
		pattern = { "markdown", "tex", "latex", "typst", "codecompanion" },
		once = true,
		callback = function()
			require("mayon.features.math_preview").setup()
		end,
	})
	require("mayon.config.keymaps").setup()
	require("mayon.config.autocmds").setup()
	vim.cmd.packadd("matchit")
	require("mayon.ui.statusline").setup()
	vim.g.mayon_config_loaded = true
	vim.g.mayon_startup_ms = (vim.uv.hrtime() - started) / 1e6
end
return M
