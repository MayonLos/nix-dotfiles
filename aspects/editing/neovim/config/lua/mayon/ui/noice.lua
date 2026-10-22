local M = {}

local function popup_width(columns)
	local available = math.max(1, columns - 4)
	return math.min(available, math.max(30, math.min(76, math.floor(columns * 0.60))))
end

local function apply_cmdline_highlights()
	local palette = require("mayon.generated").palette
	vim.api.nvim_set_hl(0, "NoiceCmdlinePopup", { fg = palette.fg, bg = palette.bg })
	vim.api.nvim_set_hl(0, "NoiceCmdlinePopupBorder", { fg = palette.border, bg = palette.bg })
	vim.api.nvim_set_hl(0, "NoiceCmdlinePopupTitle", { fg = palette.blue, bg = palette.bg })
	vim.api.nvim_set_hl(0, "NoiceCmdlineIcon", { fg = palette.blue, bg = palette.bg })
	for name in pairs(vim.api.nvim_get_hl(0, {})) do
		if name:match("^NoiceCmdlinePopupBorder") then
			vim.api.nvim_set_hl(0, name, { fg = palette.border, bg = palette.bg })
		elseif name:match("^NoiceCmdlineIcon") or name:match("^NoiceCmdlinePopupTitle") then
			vim.api.nvim_set_hl(0, name, { fg = palette.blue, bg = palette.bg })
		end
	end
end

local function resize_cmdline_view()
	local columns = vim.o.columns
	local width = popup_width(columns)
	local max_width = math.max(1, columns - 4)
	local ok, config = pcall(require, "noice.config")
	if ok and config.options and config.options.views and config.options.views.cmdline_popup then
		local size = config.options.views.cmdline_popup.size
		size.width, size.max_width = width, max_width
	end
	-- Noice caches NUI views after first use. Update those entries as well as the
	-- live popup so its next show and an in-progress command both use new geometry.
	local has_views, views = pcall(require, "noice.view")
	if has_views then
		for _, entry in ipairs(views._views or {}) do
			if entry.opts.view == "cmdline_popup" and entry.view._instance == "opts" then
				local view = entry.view
				for _, size in ipairs({ entry.opts.size, view._view_opts.size, view._opts.size }) do
					if size then
						size.width, size.max_width = width, max_width
					end
				end
				if view._nui then
					pcall(view.update_layout, view)
				end
			end
		end
	end
end

function M.setup()
	local border = { style = "rounded", padding = { 0, 1 } }
	local columns = vim.o.columns
	require("noice").setup({
		notify = { enabled = false },
		messages = { view = "mini", view_error = "mini", view_warn = "mini" },
		popupmenu = { enabled = false },
		lsp = {
			progress = { enabled = false },
			override = {
				["vim.lsp.util.convert_input_to_markdown_lines"] = true,
				["vim.lsp.util.stylize_markdown"] = true,
			},
		},
		presets = {
			bottom_search = true,
			command_palette = false,
			long_message_to_split = true,
			lsp_doc_border = true,
			inc_rename = false,
		},
		cmdline = {
			opts = {
				border = { text = { top = "" } },
				win_options = {
					winhighlight = {
						Normal = "NoiceCmdlinePopup",
						FloatBorder = "NoiceCmdlinePopupBorder",
						FloatTitle = "NoiceCmdlinePopupTitle",
						IncSearch = "",
						CurSearch = "",
						Search = "",
					},
					winbar = "",
				},
			},
			format = {
				cmdline = { title = "", icon = "❯" },
			},
		},
		views = {
			cmdline_popup = {
				border = border,
				position = { row = -7, col = "50%" },
				size = {
					width = popup_width(columns),
					height = "auto",
					min_height = 1,
					max_height = 3,
					max_width = math.max(1, columns - 4),
				},
			},
			hover = { border = border },
			popup = { border = border },
			mini = { win_options = { winblend = 0 } },
		},
		routes = {
			{ filter = { event = "msg_show", kind = "search_count" }, opts = { skip = true } },
			{
				filter = {
					event = "msg_show",
					any = {
						{ find = "%d+L, %d+B" },
						{ find = "; after #%d+" },
						{ find = "; before #%d+" },
						{ find = "%d fewer lines" },
						{ find = "%d more lines" },
						{ find = "written" },
					},
				},
				opts = { skip = true },
			},
		},
	})
	vim.api.nvim_create_autocmd("VimResized", {
		group = vim.api.nvim_create_augroup("MayonNoiceGeometry", { clear = true }),
		callback = resize_cmdline_view,
	})
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("MayonNoiceHighlights", { clear = true }),
		callback = function()
			vim.schedule(apply_cmdline_highlights)
		end,
	})
	apply_cmdline_highlights()
end

return M
