local M = {}

local function codecompanion_overrides()
	return {
		heading = {
			width = "block",
			left_pad = 1,
			right_pad = 2,
			custom = {
				user = { pattern = "^##%s+Me", icon = "󰭹 " },
				llm = { pattern = "^##%s+CodeCompanion", icon = "󰚩 " },
			},
		},
		code = {
			sign = false,
			width = "block",
			left_pad = 2,
			right_pad = 2,
			min_width = 36,
			border = "thin",
			language_pad = 1,
		},
	}
end

function M.setup()
	require("render-markdown").setup({
		file_types = { "markdown", "codecompanion" },
		completions = { lsp = { enabled = true } },
		-- Keep the formatted document visible while writing; visual selections
		-- retain the source text and its true extents.
		render_modes = { "n", "c", "t", "i" },
		win_options = { concealcursor = { rendered = "nvic" } },
		anti_conceal = { enabled = false },
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
						width = { "full", "block" },
						left_pad = 1,
						right_pad = 2,
					},
					code = {
						sign = false,
						width = "block",
						left_pad = 2,
						right_pad = 2,
						min_width = 36,
						border = "thin",
						language_pad = 1,
					},
				},
				codecompanion = codecompanion_overrides(),
			},
		},
	})
end

return M
