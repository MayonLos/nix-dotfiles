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
	local count = #picker.finder.items
	local shown = picker.list:count()
	if source:match("^grep") then
		count, shown = 0, 0
		for _, item in ipairs(picker.finder.items) do
			if not item.mayon_header then
				count = count + 1
			end
		end
		for index = 1, picker.list:count() do
			local item = picker.list:get(index)
			if item and not item.mayon_header then
				shown = shown + 1
			end
		end
	end
	local label = picker.opts.mayon_label or labels[source] or picker.title or source
	return {
		{ label, "SnacksPickerTitle" },
		{ " · ", "SnacksPickerBorder" },
		{ range(picker), "MayonPickerRange" },
		{ " · ", "SnacksPickerBorder" },
		{ ("%d / %d"):format(shown, count), "MayonPickerCount" },
	}
end

local function update_title(picker)
	local root = picker.layout and picker.layout.root
	if root and root:valid() then
		root:set_title(title(picker), "left")
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

-- Real list rows keep native scrolling, preview and confirmation aligned.
-- Headers open the first match in their file; they are never fake paths.
local function grouped_grep(opts, ctx)
	local result = require("snacks.picker.source.grep").grep(opts, ctx)
	return function(cb)
		local items = {}
		if type(result) == "function" then
			result(function(item)
				items[#items + 1] = item
			end)
		else
			items = result
		end
		local groups, order = {}, {}
		for _, item in ipairs(items) do
			local file = item.file or ""
			if not groups[file] then
				groups[file] = {}
				order[#order + 1] = file
			end
			table.insert(groups[file], item)
		end
		for _, file in ipairs(order) do
			local entries = groups[file]
			local texts = { file }
			for _, item in ipairs(entries) do
				texts[#texts + 1] = item.text
			end
			cb({
				file = file,
				cwd = entries[1].cwd,
				pos = entries[1].pos,
				text = table.concat(texts, " "),
				mayon_header = true,
				mayon_count = #entries,
			})
			for _, item in ipairs(entries) do
				cb(item)
			end
		end
	end
end

local function grep_format(item, picker)
	if item.mayon_header then
		return {
			{ vim.fn.fnamemodify(item.file, ":~:."), "SnacksPickerFile" },
			{
				col = 0,
				virt_text = { { tostring(item.mayon_count), "MayonPickerCount" } },
				virt_text_pos = "right_align",
			},
		}
	end
	local out = { { ("  %4d  "):format(item.pos and item.pos[1] or 0), "SnacksPickerRow" } }
	if item.line then
		if item.positions then
			Snacks.picker.highlight.matches(out, item.positions, Snacks.picker.highlight.offset(out))
		end
		Snacks.picker.highlight.format(item, item.line, out)
	else
		out[#out + 1] = { item.text or "", "SnacksPickerFile" }
	end
	return out
end

function M.configure(opts)
	if opts.source == "explorer" then
		opts.prompt = "❯ "
		return opts
	end

	opts.prompt = "❯ "
	opts.formatters = vim.tbl_deep_extend("force", opts.formatters or {}, { file = { filename_first = true } })
	if opts.source == "files" or opts.source == "recent" then
		opts.format = function(item, picker)
			local name = vim.fn.fnamemodify(item.file or item.text, ":t")
			local parent = vim.fn.fnamemodify(item.file or item.text, ":h")
			parent = vim.fs.relpath(picker:cwd(), parent) or vim.fn.fnamemodify(parent, ":~")
			local width = math.max(8, picker.list.win:dim().width - 4)
			local text = require("mayon.ui.text")
			name = text.truncate(name, math.max(8, math.floor(width * 0.65)))
			parent = text.truncate(parent, math.max(1, width - vim.fn.strdisplaywidth(name) - 2))
			return {
				{ name, "SnacksPickerFile" },
				{ col = 0, virt_text = { { parent, "SnacksPickerDir" } }, virt_text_pos = "right_align" },
			}
		end
	end
	opts.layout = {
		layout = {
			box = "vertical",
			width = 0.9,
			min_width = math.min(88, vim.o.columns - 4),
			max_width = vim.o.columns - 4,
			height = 0.72,
			min_height = 12,
			border = "rounded",
			title = "{title}",
			title_pos = "left",
			{
				win = "input",
				height = 1,
				border = "bottom",
			},
			{
				box = "horizontal",
				{ win = "list", border = "none", width = 0.48 },
				{ win = "preview", border = "left", title = "", width = 0.52 },
			},
		},
	}
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
				cursorline = true,
				cursorlineopt = "line",
				winhighlight = "Normal:SnacksPickerPreview,FloatBorder:SnacksPickerBorder,CursorLine:SnacksPickerPreviewCursorLine",
			},
		},
	})
	if opts.source == "grep" or opts.source == "grep_word" or opts.source == "grep_buffers" then
		opts.finder = grouped_grep
		opts.sort = function(a, b)
			if a.file ~= b.file then
				return (a.file or "") < (b.file or "")
			end
			if a.mayon_header ~= b.mayon_header then
				return a.mayon_header == true
			end
			local al, bl = a.pos and a.pos[1] or 0, b.pos and b.pos[1] or 0
			if al ~= bl then
				return al < bl
			end
			return (a.idx or 0) < (b.idx or 0)
		end
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
M.grouped_grep = grouped_grep

return M
