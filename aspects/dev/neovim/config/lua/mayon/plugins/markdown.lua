local M = {}

local function codecompanion_overrides()
	return {
		heading = { enabled = false },
		code = {
			sign = false,
			width = "block",
			left_pad = 2,
			right_pad = 2,
			min_width = 20,
			border = "thin",
			language_pad = 1,
		},
	}
end

local function setup()
	require("render-markdown").setup({
		file_types = { "markdown", "codecompanion" },
		completions = { lsp = { enabled = true } },
		-- Keep the formatted document visible while writing; visual selections
		-- retain the source text and its true extents.
		render_modes = { "n", "c", "t", "i" },
		win_options = { concealcursor = { default = "nc", rendered = "nc" } },
		anti_conceal = { enabled = true, above = 0, below = 0 },
		-- Snacks image.math_preview is the sole LaTeX renderer.
		latex = { enabled = false },
		bullet = { icons = { "•", "◦", "▪" }, right_pad = 1 },
		pipe_table = { preset = "round", cell = "padded", padding = 1 },
		quote = { icon = "▎", highlight = "RenderMarkdownQuote" },
		overrides = {
			filetype = {
				markdown = {
					heading = {
						sign = false,
						icons = { "▎ ", "▎ ", "◆ ", "◇ ", "· ", "· " },
						position = "inline",
						width = "block",
						left_pad = 1,
						right_pad = 2,
					},
					code = {
						sign = false,
						width = "block",
						left_pad = 2,
						right_pad = 2,
						min_width = 20,
						border = "thin",
						language_pad = 1,
					},
				},
				codecompanion = codecompanion_overrides(),
			},
		},
	})
end

return {
	{ "render-markdown.nvim", ft = { "markdown", "codecompanion" }, after = setup },
	{
		"img-clip.nvim",
		cmd = "PasteImage",
		after = function()
			require("img-clip").setup({
				default = {
					-- Images live beside the note, not under the shell's cwd.
					relative_to_current_file = true,
					prompt_for_file_name = false,
					-- Not wrapping vim.paste: text pastes keep their native path.
					drag_and_drop = { enabled = false },
				},
			})
		end,
	},
	{
		"vim-table-mode",
		ft = "markdown",
		before = function()
			vim.g.table_mode_corner = "|"
			-- ,tm toggles; ,tr realigns. Leader t is the terminal group.
			vim.g.table_mode_map_prefix = "<localleader>t"
			vim.g.table_mode_disable_tableize_mappings = 1
		end,
	},
}
