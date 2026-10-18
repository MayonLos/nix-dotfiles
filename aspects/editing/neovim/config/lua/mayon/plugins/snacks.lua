local M = {}

local function reduced_motion()
	local ok, generated = pcall(require, "mayon.generated")
	return ok and generated.palette and generated.palette.reducedMotion == true
end

local function sqlite3_path()
	local ok, generated = pcall(require, "mayon.generated")
	return ok and generated.tools and generated.tools.sqlite3 or nil
end

function M.setup(overrides)
	local motion_reduced = reduced_motion()
	local config = {
		input = {
			enabled = true,
			win = { border = "rounded" },
		},
		styles = {
			notification = {
				border = "rounded",
				wo = { winblend = 0 },
			},
		},
		notifier = {
			enabled = true,
			timeout = 2500,
			style = "compact",
			top_down = false,
		},
		scroll = {
			enabled = not motion_reduced,
			animate = {
				duration = { step = 12, total = 180 },
				easing = "outQuad",
			},
		},
		indent = {
			enabled = true,
			animate = { enabled = false },
			indent = { char = "│" },
			scope = { enabled = true, char = "│" },
		},
		words = { enabled = true, debounce = 150 },
		scope = { enabled = true },
		bigfile = { enabled = true, size = 1024 * 1024 },
		quickfile = { enabled = true },
		dim = { enabled = true, animate = { enabled = not motion_reduced } },
		zen = { enabled = true },
		statuscolumn = {
			enabled = true,
			left = { "mark", "sign" },
			right = { "fold", "git" },
			folds = { open = true, git_hl = true },
			git = { patterns = { "GitSign" } },
			refresh = 50,
		},
		picker = {
			enabled = true,
			ui_select = true,
			db = { sqlite3_path = sqlite3_path() },
			sources = {
				explorer = {
					layout = {
						layout = { width = 36, min_width = 36 },
					},
					win = { list = { wo = { wrap = false } } },
				},
			},
		},
		explorer = { enabled = true },
		image = {
			enabled = true,
			-- The PDF preview command owns PDFs through BufReadCmd.
			formats = {
				"png",
				"jpg",
				"jpeg",
				"gif",
				"bmp",
				"webp",
				"tiff",
				"heic",
				"avif",
				"mp4",
				"mov",
				"avi",
				"mkv",
				"webm",
				"icns",
			},
			doc = {
				enabled = true,
				-- math_preview owns the trigger and error display. Leaving Snacks'
				-- automatic placements off prevents two renderers claiming a formula.
				inline = false,
				float = false,
				max_width = 80,
				max_height = 40,
				conceal = function(_, kind)
					return kind == "math"
				end,
			},
			math = {
				enabled = true,
				latex = { font_size = "small" },
			},
			convert = {
				magick = {
					math = { "-density", 384, "{src}[{page}]", "-trim" },
				},
			},
		},
		dashboard = { enabled = false },
	}

	if overrides then
		config = vim.tbl_deep_extend("force", config, overrides)
	end

	local Snacks = require("snacks")
	Snacks.setup(config)
	-- `input.enabled` is consumed on UIEnter by Snacks' module loader. Enable it
	-- here too, so vim.ui.input is already owned by Snacks for early prompts.
	Snacks.input.enable()
end

return M
