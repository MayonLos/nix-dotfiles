local M = {}

local function reduced_motion()
	local ok, generated = pcall(require, "mayon.generated")
	return ok and generated.palette and generated.palette.reducedMotion == true
end

local function sqlite3_path()
	local ok, generated = pcall(require, "mayon.generated")
	return ok and generated.tools and generated.tools.sqlite3 or nil
end

local function setup(overrides)
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
		lazygit = {
			configure = false,
			win = { style = "float", border = "rounded", title = " lazygit ", title_pos = "left" },
		},
		terminal = {
			win = {
				border = "rounded",
				title = " terminal ",
				title_pos = "left",
				wo = { winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder" },
			},
		},
		notifier = {
			enabled = true,
			timeout = 2500,
			style = require("mayon.ui.notifications").render,
			top_down = true,
			width = { min = 28, max = 0.34 },
			height = { min = 1, max = 0.25 },
			margin = { top = 1, right = 2, bottom = 1 },
			gap = 1,
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
			indent = { enabled = false },
			scope = { enabled = true, only_current = true, char = "│", hl = "SnacksIndentScope" },
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
			right = { "git" },
			folds = { open = false, git_hl = true },
			git = { patterns = { "GitSign" } },
			refresh = 50,
		},
		picker = {
			enabled = true,
			ui_select = true,
			db = { sqlite3_path = sqlite3_path() },
			-- Keep picker visuals and source titles in one config hook. The
			-- Explorer source opts out and retains its dedicated 30-column rail.
			config = function(opts)
				return require("mayon.ui.pickers").configure(opts)
			end,
			layout = function()
				if vim.o.columns >= 100 then
					return { preset = "default", layout = { width = 0.88, height = 0.82, min_width = 40 } }
				end
				return {
					preset = "select",
					layout = {
						width = 0.88,
						height = 0.55,
						min_width = math.min(30, vim.o.columns - 4),
						max_width = vim.o.columns - 4,
					},
				}
			end,
			sources = {
				explorer = {
					actions = {
						focus_input = function(picker)
							return require("mayon.ui.pickers").explorer_search(picker)
						end,
					},
					config = function(opts)
						-- Preserve Snacks' explorer config transform and install guards
						-- before the picker exposes its actions (2.31 has no on_init).
						opts = require("snacks.picker.source.explorer").setup(opts)
						require("mayon.features.fileops").setup()
						-- The pinned explorer emits its cwd as an internal first row.
						-- The winbar already names the project, so discard that row.
						local transform = opts.transform
						opts.transform = function(item, ctx)
							if item.file == ctx.filter.cwd then
								return false
							end
							if transform then
								return transform(item, ctx)
							end
							return true
						end
						-- Tree depth remains visible as indentation without branch lines;
						-- folder icons serve as the open/closed disclosure arrows.
						opts.icons = vim.tbl_deep_extend("force", opts.icons or {}, {
							files = { dir = "▸ ", dir_open = "▾ " },
							tree = { vertical = "  ", middle = "  ", last = "  " },
						})
						opts.icons.git.enabled = false
						opts.diagnostics = false
						opts.diagnostics_open = false
						return opts
					end,
					layout = function()
						if vim.o.columns < 52 then
							return {
								preset = "select",
								hidden = { "input" },
								layout = {
									width = 0.82,
									min_width = vim.o.columns - 4,
									max_width = vim.o.columns - 4,
									height = 0.55,
								},
							}
						end
						local width = 30
						return {
							preset = "sidebar",
							hidden = { "input" },
							preview = false,
							layout = { width = width, min_width = width, max_width = width, height = 0 },
						}
					end,
					on_show = function(picker)
						local win = picker.list.win.win
						local title = vim.fn.fnamemodify(picker:cwd(), ":t"):upper():gsub("%%", "%%%%")
						picker.opts.title = title
						_G.MayonExplorerStatusColumn = function()
							local target = tonumber(vim.g.statusline_winid)
							if
								not target
								or not vim.api.nvim_win_is_valid(target)
								or vim.bo[vim.api.nvim_win_get_buf(target)].filetype ~= "snacks_picker_list"
							then
								target = win
							end
							return vim.v.lnum == vim.api.nvim_win_get_cursor(target)[1]
									and "%#MayonExplorerCursor#▎%*"
								or " "
						end
						local options = {
							number = true,
							relativenumber = false,
							numberwidth = 1,
							signcolumn = "no",
							statuscolumn = "%!v:lua.MayonExplorerStatusColumn()",
							cursorline = true,
							cursorlineopt = "line",
							winbar = "%#MayonExplorerTitle# " .. title .. " %*",
						}
						-- Snacks reapplies opts.wo during its final layout pass.
						picker.list.win.opts.wo = vim.tbl_extend("force", picker.list.win.opts.wo, options)
						picker.layout.win_opts.list.wo =
							vim.tbl_extend("force", picker.layout.win_opts.list.wo, options)
						vim.schedule(function()
							if not vim.api.nvim_win_is_valid(win) then
								return
							end
							for key, value in pairs(options) do
								vim.wo[win][key] = value
							end
						end)
					end,
					on_change = function(picker)
						local title = vim.fn.fnamemodify(picker:cwd(), ":t"):upper():gsub("%%", "%%%%")
						if picker.opts.title ~= title then
							picker.opts.on_show(picker)
						end
					end,
					format = function(item, picker)
						local depth, parent = 0, item.parent
						while parent and parent.file ~= picker:cwd() do
							depth, parent = depth + 1, parent.parent
						end
						local prefix = string.rep("  ", math.min(depth, 8))
						local icon = item.dir and ((item.open and "▾ " or "▸ ") .. "󰉋 ") or "    "
						local name = vim.fn.fnamemodify(item.file, ":t")
						local width = math.max(5, picker.list.win:dim().width - #prefix - 6 - (item.status and 2 or 0))
						local text = require("mayon.ui.text")
						if vim.fn.strdisplaywidth(name) > width then
							local ext = name:match("(%.[^.]+)$") or ""
							name = text.truncate(name:sub(1, #name - #ext), math.max(2, width - #ext)) .. ext
						end
						local result = { { prefix }, { icon, "Directory" }, { name, "MayonExplorerFile" } }
						if item.status then
							vim.list_extend(result, require("snacks.picker.format").file_git_status(item, picker))
						end
						return result
					end,
					formatters = { file = { truncate = "center", min_width = 12 } },
					win = {
						list = {
							border = "right",
							wo = {
								wrap = false,
							},
						},
					},
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
		dashboard = {
			enabled = true,
			config = function(opts)
				local custom = require("mayon.ui.dashboard").config()
				for key, value in pairs(custom) do
					opts[key] = value
				end
			end,
		},
	}

	if overrides then
		config = vim.tbl_deep_extend("force", config, overrides)
	end

	local Snacks = require("snacks")
	-- These UIEnter setups do not contribute to the first dashboard frame.
	-- Preserve their configuration, then initialize at the existing scheduled
	-- VeryLazy event (also explicitly fired by headless integration tests).
	local deferred = {}
	for _, name in ipairs({ "scroll", "input", "scope", "picker" }) do
		if config[name] and config[name].enabled then
			deferred[#deferred + 1] = name
			config[name].enabled = false
		end
	end
	Snacks.setup(config)
	vim.api.nvim_create_autocmd("User", {
		group = vim.api.nvim_create_augroup("MayonDeferredSnacks", { clear = true }),
		pattern = "MayonVeryLazy",
		once = true,
		callback = function()
			for _, name in ipairs(deferred) do
				Snacks.config[name].enabled = true
				local module = Snacks[name]
				if module.setup then
					module.setup()
				elseif module.enable then
					module.enable()
				end
			end
		end,
	})
	-- Keep even prompts issued before UIEnter on Snacks, without importing the
	-- input renderer (and its highlight/util graph) until there is a prompt.
	vim.ui.input = function(opts, on_confirm)
		return Snacks.input(opts, on_confirm)
	end
end

return { {
	"snacks.nvim",
	lazy = false,
	after = function()
		setup()
	end,
} }
