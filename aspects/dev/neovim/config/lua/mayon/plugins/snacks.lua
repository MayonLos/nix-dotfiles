local M = {}

local function middle_truncate_filename(name, width)
	if vim.fn.strdisplaywidth(name) <= width then
		return name
	end
	if width <= 1 then
		return width > 0 and "…" or ""
	end
	local extension = name:match("(%.[^%.]+)$") or ""
	local stem = extension ~= "" and name:sub(1, #name - #extension) or name
	local available = width - vim.fn.strdisplaywidth("…") - vim.fn.strdisplaywidth(extension)
	if available <= 0 then
		return require("mayon.ui.text").truncate(name, width)
	end
	local left_width = math.ceil(available / 2)
	local right_width = available - left_width
	local left, used = "", 0
	for index = 0, vim.fn.strchars(stem) - 1 do
		local char = vim.fn.strcharpart(stem, index, 1)
		local char_width = vim.fn.strdisplaywidth(char)
		if used + char_width > left_width then
			break
		end
		left, used = left .. char, used + char_width
	end
	local right = ""
	used = 0
	for index = vim.fn.strchars(stem) - 1, 0, -1 do
		local char = vim.fn.strcharpart(stem, index, 1)
		local char_width = vim.fn.strdisplaywidth(char)
		if used + char_width > right_width then
			break
		end
		right, used = char .. right, used + char_width
	end
	return left .. "…" .. right .. extension
end

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
			win = { style = "float", border = "rounded", title = " Git · Lazygit ", title_pos = "center" },
		},
		terminal = {
			win = {
				border = "rounded",
				title = " Terminal · Snacks ",
				title_pos = "center",
				wo = { winhighlight = "Normal:NormalFloat,FloatBorder:FloatBorder" },
			},
		},
		notifier = {
			enabled = true,
			timeout = 3000,
			style = require("mayon.ui.notifications").render,
			filter = require("mayon.ui.notifications").filter,
			top_down = true,
			width = { min = 28, max = 0.34 },
			height = { min = 1, max = 0.25 },
			margin = { top = 1, right = 2, bottom = 1 },
			gap = 1,
		},
		scroll = {
			enabled = not motion_reduced,
			filter = function(buf)
				return not motion_reduced
					and vim.bo[buf].filetype ~= "bigfile"
					and vim.bo[buf].buftype ~= "terminal"
					and vim.b[buf].snacks_scroll ~= false
					and vim.g.snacks_scroll ~= false
			end,
			animate = {
				duration = { step = 10, total = 120 },
				easing = "outQuad",
			},
		},
		indent = {
			enabled = true,
			animate = { enabled = false },
			indent = { enabled = true, char = "│", hl = "SnacksIndent" },
			scope = { enabled = true, only_current = true, char = "│", hl = "SnacksIndentScope" },
		},
		words = { enabled = true, debounce = 150 },
		scope = { enabled = true },
		bigfile = { enabled = true, size = 1024 * 1024 },
		quickfile = { enabled = true },
		dim = { enabled = true, animate = { enabled = not motion_reduced } },
		zen = {
			enabled = true,
			toggles = { dim = true, git_signs = false, mini_diff_signs = false },
			show = { statusline = true, tabline = false },
			win = {
				width = 100,
				border = "none",
				title = "",
				backdrop = { transparent = false },
				wo = { winbar = "", statuscolumn = "", signcolumn = "no", number = false, relativenumber = false },
			},
			on_open = function(win)
				vim.api.nvim_win_set_config(win.win, { border = "none", title = "" })
				vim.wo[win.win].winbar = ""
				vim.wo[win.win].winhighlight = "NormalFloat:Normal,Normal:Normal,NormalNC:Normal"
				vim.o.showtabline = 0
			end,
			on_close = function()
				vim.o.showtabline = 2
			end,
		},
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
			-- Explorer source opts out and retains its on-demand 34-column sidebar.
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
						return {
							preview = false,
							layout = {
								box = "vertical",
								position = "left",
								width = 34,
								height = 0,
								border = "none",
								{ win = "input", height = 1, border = "rounded" },
								{ win = "list", border = "none" },
							},
						}
					end,
					on_show = function(picker)
						local win = picker.list.win.win
						local title = "filter"
						picker.opts.title = title
						-- Keep the native recursive filter; render its empty hint instead of
						-- an extra project header or a constantly changing counter.
						if not picker.input._mayon_filter_hint then
							local update = picker.input.update
							picker.input.update = function(input, ...)
								update(input, ...)
								if input.win:buf_valid() then
									local native = vim.api.nvim_get_namespaces()["snacks.picker.input"]
									if native then
										pcall(vim.api.nvim_buf_del_extmark, input.win.buf, native, 999)
									end
									local ns = vim.api.nvim_create_namespace("MayonExplorerFilter")
									vim.api.nvim_buf_clear_namespace(input.win.buf, ns, 0, -1)
									if input:get() == "" then
										vim.api.nvim_buf_set_extmark(
											input.win.buf,
											ns,
											0,
											0,
											{ virt_text = { { "filter", "Comment" } }, virt_text_pos = "eol" }
										)
									end
								end
							end
							picker.input._mayon_filter_hint = true
							picker.input:update()
						end
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
							winbar = "",
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
						local title = "filter"
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
						local icon, icon_hl
						if item.dir then
							icon, icon_hl = (item.open and "▾ " or "▸ ") .. "󰉋 ", "Directory"
						else
							icon, icon_hl = require("mayon.ui.icons").get(item.file)
						end
						local name = vim.fn.fnamemodify(item.file, ":t")
						local width = math.max(
							1,
							picker.list.win:dim().width
								-- Native list rows add a leading space; our rail also
								-- consumes one text cell through statuscolumn.
								- 2
								- vim.fn.strdisplaywidth(prefix)
								- vim.fn.strdisplaywidth(icon)
								- (item.status and 2 or 0)
						)
						name = middle_truncate_filename(name, width)
						local result = { { prefix }, { icon, icon_hl }, { name, "MayonExplorerFile" } }
						if item.status then
							vim.list_extend(result, require("snacks.picker.format").file_git_status(item, picker))
						end
						return result
					end,
					win = {
						input = { title = "", wo = { winbar = "" } },
						list = {
							border = "none",
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
			mermaid = { enabled = false },
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
	vim.ui.select = function(items, opts, on_choice)
		return Snacks.picker.select(items, opts, on_choice)
	end
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
