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
		code = { width = "block", left_pad = 1, right_pad = 1 },
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
		overrides = {
			filetype = {
				markdown = {
					heading = { width = "block", left_pad = 1, right_pad = 2 },
					code = { width = "block", left_pad = 1, right_pad = 1 },
				},
				codecompanion = codecompanion_overrides(),
			},
		},
	})
end

return M
