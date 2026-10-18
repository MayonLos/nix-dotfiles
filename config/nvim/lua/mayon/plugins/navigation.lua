local M = {}

function M.setup()
	require("fzf-lua").setup({
		winopts = {
			-- A full backdrop avoids a dark rectangle around the picker surface.
			backdrop = 100,
			border = "rounded",
			width = 0.86,
			height = 0.80,
			row = 0.5,
			col = 0.5,
			preview = { layout = "flex", horizontal = "right:55%", vertical = "down:45%", scrollbar = false },
		},
		hls = {
			normal = "FzfLuaSurface",
			border = "FzfLuaSurfaceBorder",
			title = "FzfLuaSurfaceTitle",
			preview_normal = "FzfLuaSurface",
			preview_border = "FzfLuaSurfaceBorder",
			preview_title = "FzfLuaSurfaceTitle",
			fzf = {
				normal = "FzfLuaSurface",
				border = "FzfLuaSurfaceBorder",
				separator = "FzfLuaSurfaceBorder",
				gutter = "FzfLuaSurface",
				prompt = "FzfLuaSurfaceTitle",
				pointer = "FzfLuaSurfaceTitle",
				marker = "FzfLuaSurfaceTitle",
			},
		},
		fzf_colors = true,
		fzf_opts = { ["--pointer"] = "▌", ["--marker"] = "✓" },
		file_icon_padding = " ",
		files = { prompt = "Files❯ ", file_icons = true, git_icons = true },
		previewers = { bat = { cmd = "bat", args = "--style=numbers,changes --color always" } },
	})
	for _, spec in ipairs({
		{ "<leader>ff", "files", "Find files" },
		{ "<leader>fg", "live_grep", "Live grep" },
		{ "<leader>fb", "buffers", "Buffers" },
		{ "<leader>fr", "oldfiles", "Recent files" },
		{ "<leader>fh", "helptags", "Help" },
		{ "<leader>f.", "blines", "Buffer lines" },
	}) do
		vim.keymap.set("n", spec[1], "<cmd>FzfLua " .. spec[2] .. "<cr>", { desc = spec[3] })
	end
end

return M
