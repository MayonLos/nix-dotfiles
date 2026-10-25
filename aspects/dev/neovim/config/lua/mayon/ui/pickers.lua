-- Explorer navigation stays in its sidebar; its search opens a normal picker.
local M = {}

local labels = {
	files = "文件",
	grep = "全文搜索",
	grep_word = "全文搜索",
	grep_buffers = "缓冲区搜索",
	lsp_symbols = "符号",
	lsp_workspace_symbols = "工作区符号",
	buffers = "缓冲区",
	recent = "最近文件",
	help = "帮助",
	keymaps = "快捷键",
	diagnostics = "诊断",
}

local function range(picker)
	local cwd = picker:cwd()
	return vim.fn.fnamemodify(cwd, ":~")
end

local function title(picker)
	local source = picker.opts.source or "search"
	local shown = picker.list:count()
	local label = source:match("^grep") and "grep"
		or (picker.opts.mayon_label or labels[source] or picker.title or source)
	return {
		{ label, "SnacksPickerTitle" },
		{ " · ", "SnacksPickerBorder" },
		{ tostring(shown) .. (source:match("^grep") and " matches" or " items"), "MayonPickerCount" },
	}
end

local function update_title(picker)
	local root = picker.layout and picker.layout.root
	if root and root:valid() then
		root:set_title(title(picker), "center")
	end
end

local function show_picker(picker)
	local win = picker.list.win.win
	if not picker.input._mayon_totals then
		local update = picker.input.update
		picker.input.update = function(input, ...)
			update(input, ...)
			local ns = vim.api.nvim_get_namespaces()["snacks.picker.input"]
			if ns and input.win:buf_valid() then
				pcall(vim.api.nvim_buf_del_extmark, input.win.buf, ns, 999)
			end
		end
		picker.input._mayon_totals = true
	end
	if not picker._mayon_title_wrapped then
		local update = picker.update_titles
		picker.update_titles = function(self, ...)
			update(self, ...)
			update_title(self)
		end
		picker._mayon_title_wrapped = true
	end
	local function rail()
		local current = tonumber(vim.g.statusline_winid) or win
		if
			vim.api.nvim_win_is_valid(current)
			and vim.bo[vim.api.nvim_win_get_buf(current)].filetype == "snacks_picker_list"
			and vim.v.lnum == vim.api.nvim_win_get_cursor(current)[1]
		then
			return "%#MayonPickerRail#▎%*"
		end
		return " "
	end
	_G.MayonPickerStatusColumn = rail
	local options = {
		cursorline = true,
		cursorlineopt = "line",
		number = true,
		numberwidth = 1,
		relativenumber = false,
		signcolumn = "no",
		statuscolumn = "%!v:lua.MayonPickerStatusColumn()",
	}
	picker.list.win.opts.wo = vim.tbl_extend("force", picker.list.win.opts.wo, options)
	picker.layout.win_opts.list.wo = vim.tbl_extend("force", picker.layout.win_opts.list.wo, options)
	vim.schedule(function()
		if vim.api.nvim_win_is_valid(win) then
			for key, value in pairs(options) do
				vim.wo[win][key] = value
			end
		end
	end)
	update_title(picker)
end

-- One match per row; paths stay at the right so the text remains easy to scan.
local function grep_format(item, picker)
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

-- Keep navigation compact; use context where choosing a match needs code/diff.
function M.preview_default(source)
	source = source or ""
	return source:match("^grep") ~= nil
		or source:match("^lsp_") ~= nil
		or source:match("^git_") ~= nil
		or source:match("^diagnostics") ~= nil
end

function M.layout(preview)
	local wide = vim.o.columns >= 120 and vim.o.lines >= 28
	local visible = preview and wide
	return {
		preview = visible,
		layout = {
			box = "horizontal",
			backdrop = false,
			width = visible and 0.78 or 0.58,
			min_width = math.min(58, vim.o.columns - 4),
			max_width = math.min(visible and 142 or 90, vim.o.columns - 4),
			height = visible and math.min(18, vim.o.lines - 8) or 8,
			border = "rounded",
			title = "{title}",
			title_pos = "center",
			{
				box = "vertical",
				{ win = "input", height = 1, border = "bottom" },
				{ win = "list", border = "none" },
			},
			{ win = "preview", width = 0.52, border = "left" },
		},
	}
end

function M.configure(opts)
	-- Keep native Snacks formatters on the same colored, configured devicon set.
	require("mayon.ui.icons").ensure()
	if opts.source == "explorer" then
		opts.prompt = "⌕ "
		return opts
	end

	opts.prompt = "❯ "
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
	local prior_show, prior_change = opts.on_show, opts.on_change
	opts.on_show = function(picker)
		show_picker(picker)
		if prior_show then
			prior_show(picker)
		end
	end
	opts.on_change = function(picker, item)
		update_title(picker)
		if prior_change then
			prior_change(picker, item)
		end
	end
	return opts
end

function M.explorer_search(picker)
	return Snacks.picker.files({ cwd = picker:cwd(), mayon_label = "Explorer 搜索" })
end

M.labels = labels
M.grep_format = grep_format

return M
