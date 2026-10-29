local M = {}
function M.setup()
	local started = vim.uv.hrtime()
	require("mayon.config.options").setup()
	require("vim._core.ui2").enable()
	require("mayon.ui.theme").setup()
	require("mayon.config.loader").setup()
	-- Rename stays protected even before the explorer is opened. Explorer trash
	-- is wired by its config callback, before any action can run.
	require("snacks").rename.rename_file = function(...)
		return require("mayon.features.fileops").rename_file(...)
	end
	local function sessions()
		local feature = require("mayon.features.sessions")
		feature.setup()
		return feature
	end
	vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile", "DirChanged" }, {
		once = true,
		callback = sessions,
	})
	for lhs, method in pairs({ ps = "load", pl = "last", pd = "disable" }) do
		vim.keymap.set("n", "<leader>" .. lhs, function()
			sessions()[method]()
		end, {
			desc = ({ ps = "Load Project Session", pl = "Load Last Session", pd = "Pause Session Saving" })[lhs],
		})
	end
	vim.api.nvim_create_user_command("Urls", function(cmd)
		require("mayon.features.urls").pick_dir(cmd.args)
	end, { nargs = "?", complete = "dir", desc = "Pick URL from Directory" })
	vim.api.nvim_create_user_command("UrlsBuffer", function()
		require("mayon.features.urls").pick_buffer()
	end, { desc = "Pick URL from Buffer" })
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
	require("mayon.ui.tabline").setup()
	require("mayon.ui.extras").setup()
	vim.api.nvim_create_autocmd("FileType", {
		once = true,
		callback = function()
			vim.cmd.packadd("matchit")
		end,
	})
	-- The dashboard's first frame needs only this rail. Load the full editing
	-- statusline after that frame, or synchronously when a document is opened.
	vim.o.statusline = "%#MayonModeNumber# ● %*N · dashboard%=%#StatusLine#q Quit "
	local function statusline()
		require("mayon.ui.statusline").setup()
	end
	vim.api.nvim_create_autocmd("FileType", {
		callback = function(ev)
			if ev.match ~= "snacks_dashboard" then
				statusline()
				return true
			end
		end,
	})
	vim.api.nvim_create_autocmd("UIEnter", {
		once = true,
		callback = function()
			vim.schedule(function()
				statusline()
				local s = sessions()
				s.auto_restore()
			end)
		end,
	})
	vim.g.mayon_config_loaded = true
	vim.g.mayon_startup_ms = (vim.uv.hrtime() - started) / 1e6
end
return M
