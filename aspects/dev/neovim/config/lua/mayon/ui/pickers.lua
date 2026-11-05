-- One shared rail helper and one picker layout; the explorer sidebar reuses it.
local M = {}

local labels = {
	files = "Files",
	grep = "Search Text",
	grep_word = "Search Text",
	grep_buffers = "Search Buffers",
	lsp_symbols = "Symbols",
	lsp_workspace_symbols = "Workspace Symbols",
	buffers = "Buffers",
	recent = "Recent Files",
	help = "Help",
	keymaps = "Keymaps",
	diagnostics = "Diagnostics",
}

-- A single statuscolumn helper draws the blue "▎" cursor rail for every picker
-- list and the explorer sidebar. The expression calls this module directly, so
-- no `_G.Mayon*` function has to survive into the global namespace.
function M.statuscolumn()
	local win = tonumber(vim.g.statusline_winid)
	if not win or not vim.api.nvim_win_is_valid(win) then
		return " "
	end
	local buf = vim.api.nvim_win_get_buf(win)
	if vim.bo[buf].filetype ~= "snacks_picker_list" then
		return " "
	end
	return vim.v.lnum == vim.api.nvim_win_get_cursor(win)[1] and "%#MayonPickerRail#▎%*" or " "
end

function M.rail()
	return "%!v:lua.require'mayon.ui.pickers'.statuscolumn()"
end

-- One match per row; paths stay at the right so the text remains easy to scan.
local function grep_format(item)
	local out = { { ("%4d  "):format(item.pos and item.pos[1] or 0), "SnacksPickerRow" } }
	if item.line then
		if item.positions then
			Snacks.picker.highlight.matches(out, item.positions, Snacks.picker.highlight.offset(out))
		end
		Snacks.picker.highlight.format(item, item.line, out)
	else
		out[#out + 1] = { item.text or "", "SnacksPickerFile" }
	end
	local icon, hl = require("mayon.ui.icons").get(item.file or "")
	out[#out + 1] = {
		col = 0,
		virt_text = { { " " .. icon, hl }, { vim.fn.fnamemodify(item.file or "", ":t"), "SnacksPickerDir" } },
		virt_text_pos = "right_align",
	}
	return out
end

-- The document stays visible above a bottom search panel. File/content
-- selection gets a preview on wide editors; Alt-p remains an explicit choice.
function M.preview_default(source)
	return vim.o.columns >= 120 and vim.tbl_contains({ "files", "recent", "grep", "grep_word" }, source)
end

-- Editor columns not taken by AI side panels. The picker floats over this
-- span instead of splitting: a split resizes every window around it, and a
-- CLI running in an AI terminal redraws badly after each resize.
local function document_span()
	local panels = require("mayon.ui.ai_panels")
	local left, right
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if vim.api.nvim_win_get_config(win).relative == "" and not panels.is_panel(vim.api.nvim_win_get_buf(win)) then
			local col = vim.api.nvim_win_get_position(win)[2]
			local width = vim.api.nvim_win_get_width(win)
			left = math.min(left or col, col)
			right = math.max(right or 0, col + width)
		end
	end
	if not left then
		return 0, vim.o.columns
	end
	return left, right - left
end

function M.layout(preview)
	local wide = vim.o.columns >= 120
	local height = math.max(8, math.floor(vim.o.lines * (wide and 0.42 or 0.52)))
	local col, width = document_span()
	return {
		preview = preview or false,
		layout = {
			box = "vertical",
			backdrop = false,
			position = "float",
			-- Bottom-anchored just above the global statusline (cmdheight=0).
			row = -1,
			col = col,
			width = width - 2,
			height = height,
			border = require("mayon.util").border,
			{ win = "input", height = 1, border = "bottom" },
			{
				box = wide and "horizontal" or "vertical",
				{ win = "list", border = "none" },
				{
					win = "preview",
					width = wide and 0.55 or nil,
					height = not wide and 0.5 or nil,
					border = wide and "left" or "top",
				},
			},
		},
	}
end

function M.explorer_filter(picker)
	picker:focus("input", { show = true })
end

function M.explorer_filter_close(picker)
	picker.input:set("")
	-- The delayed input callback will stop after its window is hidden.
	-- Rerun the native finder now so the unfiltered tree is restored.
	picker:find({ refresh = false })
	picker:focus("list")
	if not picker.layout:is_hidden("input") then
		picker:toggle("input", { enable = false })
	end
end

function M.configure(opts)
	-- Keep native Snacks formatters on the same colored, configured devicon set.
	require("mayon.ui.icons").ensure()
	if opts.source == "explorer" then
		opts.prompt = "⌕ "
		opts.actions = vim.tbl_extend("force", opts.actions or {}, {
			explorer_filter = M.explorer_filter,
			explorer_filter_close = M.explorer_filter_close,
		})
		opts.win = vim.tbl_deep_extend("force", opts.win or {}, {
			list = { keys = { ["/"] = "explorer_filter" } },
			input = { keys = { ["<Esc>"] = { "explorer_filter_close", mode = { "n", "i" } } } },
		})
		return opts
	end

	opts.prompt = "❯ "
	-- Public picker title; the old footer/count patch is gone.
	opts.title = opts.title or opts.mayon_label or labels[opts.source]
	opts.formatters = vim.tbl_deep_extend("force", opts.formatters or {}, { file = { filename_first = true } })
	if opts.source == "files" or opts.source == "recent" then
		opts.format = function(item, picker)
			local path = item.file or item.text
			local name = vim.fn.fnamemodify(path, ":t")
			local icon, icon_hl = require("mayon.ui.icons").get(path)
			local icon_width = vim.fn.strdisplaywidth(icon)
			local parent = vim.fn.fnamemodify(path, ":h")
			parent = vim.fs.relpath(picker:cwd(), parent) or vim.fn.fnamemodify(parent, ":~")
			local width = math.max(8, picker.list.win:dim().width - 4 - icon_width)
			local text = require("mayon.ui.text")
			name = text.truncate(name, math.max(8, math.floor(width * 0.65)))
			local parent_width = math.max(1, width - vim.fn.strdisplaywidth(name) - 2)
			parent = text.truncate(parent, parent_width)
			return {
				{ icon, icon_hl },
				{ name, "SnacksPickerFile" },
				{ col = 0, virt_text = { { parent, "SnacksPickerDir" } }, virt_text_pos = "right_align" },
			}
		end
	end
	local preview = M.preview_default(opts.source)
	opts.layout = function()
		return M.layout(preview)
	end
	opts.actions = vim.tbl_extend("force", opts.actions or {}, {
		toggle_preview = function(picker)
			preview = not preview
			picker:set_layout()
		end,
	})

	opts.win = vim.tbl_deep_extend("force", opts.win or {}, {
		input = { wo = { winhighlight = "Normal:SnacksPickerInput,FloatBorder:SnacksPickerInputBorder" } },
		list = {
			wo = {
				cursorline = true,
				cursorlineopt = "line",
				number = true,
				numberwidth = 1,
				relativenumber = false,
				signcolumn = "no",
				statuscolumn = M.rail(),
				winhighlight = "Normal:SnacksPickerList,FloatBorder:SnacksPickerBorder,CursorLine:SnacksPickerListCursorLine",
			},
		},
		preview = {
			wo = {
				winbar = "%#FloatTitle# Preview · Alt-p %*",
				cursorline = true,
				cursorlineopt = "line",
				winhighlight = "Normal:SnacksPickerPreview,NormalNC:SnacksPickerPreview,WinBar:FloatTitle,SignColumn:SnacksPickerPreview,LineNr:SnacksPickerDir,FloatBorder:SnacksPickerBorder,CursorLine:SnacksPickerPreviewCursorLine",
			},
		},
	})
	if opts.source == "grep" or opts.source == "grep_word" or opts.source == "grep_buffers" then
		opts.format = grep_format
	end
	return opts
end

function M.explorer_search(picker)
	return Snacks.picker.files({ cwd = picker:cwd(), mayon_label = "Explorer 搜索" })
end

M.labels = labels
M.grep_format = grep_format

return M
