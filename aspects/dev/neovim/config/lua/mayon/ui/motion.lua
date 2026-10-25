local M = {}

function M.reduced_motion()
	if vim.env.NVIM_REDUCED_MOTION == "1" then
		return true
	end
	local ok, generated = pcall(require, "mayon.generated")
	return ok and generated.palette and generated.palette.reducedMotion == true or false
end

function M.config()
	local palette = require("mayon.generated").palette
	local muted_blue = require("mayon.ui.theme").blend(palette.blue, palette.bg, 0.18)
	return {
		enabled = not M.reduced_motion(),
		autoreload = true,
		refresh_interval_ms = 12,
		text_change_batch_timeout_ms = 40,
		overwrite = {
			auto_map = true,
			yank = { enabled = true, default_animation = "fade" },
			paste = { enabled = true, default_animation = "reverse_fade" },
			search = { enabled = true, default_animation = "fade", next_mapping = "n", prev_mapping = "N" },
			undo = { enabled = true, default_animation = "fade", undo_mapping = "u" },
			redo = { enabled = true, default_animation = "fade", redo_mapping = "<C-r>" },
		},
		animations = {
			fade = {
				max_duration = 260,
				min_duration = 80,
				easing = "outQuad",
				chars_for_max_duration = 10,
				from_color = muted_blue,
				to_color = palette.bg,
			},
			reverse_fade = {
				max_duration = 280,
				min_duration = 90,
				easing = "outQuad",
				chars_for_max_duration = 10,
				from_color = muted_blue,
				to_color = palette.bg,
			},
		},
		hijack_ft_disabled = {
			"bigfile",
			"checkhealth",
			"help",
			"qf",
			"snacks_dashboard",
			"snacks_picker_list",
			"snacks_terminal",
		},
	}
end

function M.setup()
	local config = M.config()
	require("tiny-glimmer").setup(config)
	return config
end

return M
