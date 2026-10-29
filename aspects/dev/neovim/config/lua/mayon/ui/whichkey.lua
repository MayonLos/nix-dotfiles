local M = {}
local max_window_width = 118

function M.geometry(columns)
	columns = math.max(1, columns or vim.o.columns)
	local width = math.max(1, math.min(max_window_width, columns - 2, math.floor(columns * 0.69)))
	local col = math.floor((columns - width) / 2)
	local layout_columns = width >= 70 and 4 or width >= 50 and 3 or width >= 32 and 2 or 1
	local column_width = math.max(1, math.floor(width / layout_columns - 2))
	return { width = width, col = col, column_width = column_width, columns = layout_columns }
end

local function apply_highlights()
	local c = require("mayon.generated").palette
	vim.api.nvim_set_hl(0, "WhichKey", { fg = c.blue, bg = c.bg, bold = true })
	vim.api.nvim_set_hl(0, "WhichKeyDesc", { fg = c.fg, bg = c.bg })
	vim.api.nvim_set_hl(0, "WhichKeyGroup", { fg = c.muted, bg = c.bg })
	vim.api.nvim_set_hl(0, "WhichKeySeparator", { fg = c.muted, bg = c.bg })
	vim.api.nvim_set_hl(0, "WhichKeyTitle", { fg = c.muted, bg = c.bg, bold = true })
	vim.api.nvim_set_hl(0, "WhichKeyNormal", { fg = c.fg, bg = c.bg })
	vim.api.nvim_set_hl(0, "WhichKeyIcon", { fg = c.blue, bg = c.bg })
	local edge = require("mayon.ui.theme").float_edge()
	vim.api.nvim_set_hl(0, "WhichKeyBorder", { fg = edge, bg = c.bg })
end

local groups = {
	{ "<leader>s", "Search", "󰍉" },
	{ "<leader>g", "Git", "󰊢" },
	{ "<leader>l", "LSP", "󰒋" },
	{ "<leader>d", "Debug", "󰃤" },
	{ "<leader>a", "AI", "󰧑" },
	{ "<leader>t", "Terminal", "" },
	{ "<leader>u", "UI", "󰙵" },
	{ "<leader>f", "Files", "󰈔" },
	{ "<leader>p", "Project", "󰉋" },
	{ "<leader>r", "Run", "󰑮" },
	{ "<leader>x", "List", "󰈙" },
	{ "<leader>m", "Multicursor", "󰗧", { "n", "x" } },
	{ "<leader>c", "Code", "󰅩" },
	{ "<leader>b", "Buffers", "󰈙" },
	{ "<leader>q", "Quit", "󰗼" },
	{ "<leader>n", "Notes", "󰎞" },
}

local function group_spec()
	local spec = {
		{ "<leader><leader>", desc = "Find Files and Text" },
		{ "<leader>/", desc = "Search Text" },
		{ "<leader>,", desc = "Switch Buffers" },
	}
	for _, group in ipairs(groups) do
		spec[#spec + 1] = {
			group[1],
			group = group[2],
			icon = { icon = group[3], hl = "WhichKeyIcon" },
			mode = group[4],
		}
	end
	return spec
end

-- The native renderer packs each box to its content width. Pad between its
-- existing key spans so the four boxes occupy equal quarters of the strip;
-- extmarks move with the inserted whitespace and native key handling is intact.
local function spread_columns(win)
	local buf = vim.api.nvim_win_get_buf(win)
	local rows = {}
	for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true })) do
		if mark[4].hl_group == "WhichKey" then
			rows[mark[2]] = rows[mark[2]] or {}
			table.insert(rows[mark[2]], mark[3])
		end
	end
	local width = vim.api.nvim_win_get_width(win)
	local boxes = 1
	for _, columns in pairs(rows) do
		boxes = math.max(boxes, #columns)
	end
	local modifiable = vim.bo[buf].modifiable
	vim.bo[buf].modifiable = true
	for row, columns in pairs(rows) do
		table.sort(columns)
		if #columns > 1 then
			local text = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
			local deltas = { 0 }
			for column = 2, #columns do
				local current = vim.fn.strdisplaywidth(text:sub(1, columns[column]))
				deltas[column] = math.max(0, (column - 1) * math.floor(width / boxes) + 2 - current)
			end
			for column = #columns, 2, -1 do
				local pad = math.max(0, deltas[column] - deltas[column - 1])
				if pad > 0 then
					vim.api.nvim_buf_set_text(buf, row, columns[column], row, columns[column], { string.rep(" ", pad) })
				end
			end
		end
	end
	vim.bo[buf].modifiable = modifiable
end

local function install_title()
	local view = require("which-key.view")
	if view._mayon_title then
		return
	end
	view._mayon_title = true
	-- The pinned renderer exposes the actual filtered subtree count. Keep
	-- labels short while making the size of each collapsed group explicit.
	local item = view.item
	view.item = function(node, opts)
		local result = item(node, opts)
		if
			result.group
			and node.desc
			and node:count() > 0
			and not node:can_expand()
			and not (opts and opts.group == false)
		then
			result.desc = result.desc .. " +" .. node:count()
		end
		return result
	end
	local render = view.show
	view.show = function(...)
		local geometry = M.geometry(vim.o.columns)
		local options = require("which-key.config").options
		options.win.width = geometry.width
		options.win.col = geometry.col
		options.layout.width = { min = geometry.column_width, max = geometry.column_width }
		local result = render(...)
		local popup = view.view
		local win = popup and popup.win
		if win and vim.api.nvim_win_is_valid(win) then
			local buf = vim.api.nvim_win_get_buf(win)
			if vim.bo[buf].filetype == "wk" then
				spread_columns(win)
			end
		end
		return result
	end
end

function M.config()
	return {
		spec = group_spec(),
		delay = function(ctx)
			return ctx.plugin and 0 or 200
		end,
		-- The root grid is at its height budget; <leader>1-9 stay in the keymap picker.
		filter = function(mapping)
			return type(mapping.desc) == "string"
				and mapping.desc ~= ""
				and not mapping.desc:match("^Jump to Buffer %d$")
		end,
		sort = { "local", "group", "manual", "alphanum", "mod" },
		expand = 0,
		icons = { mappings = true, colors = false, separator = " ", group = "" },
		replace = { desc = { { "^%+", "+" } } },
		show_help = false,
		show_keys = false,
		win = {
			border = "single",
			row = -1,
			col = M.geometry().col,
			width = M.geometry().width,
			height = { min = 4, max = 10 },
			padding = { 0, 1 },
			title = true,
			title_pos = "center",
			wo = { winblend = 0 },
		},
		layout = {
			width = { min = M.geometry().column_width, max = M.geometry().column_width },
			spacing = 2,
		},
		plugins = {
			mayon_macros = true,
			marks = true,
			registers = true,
			spelling = { enabled = true },
			presets = {
				operators = true,
				motions = true,
				text_objects = true,
				windows = true,
				nav = true,
				z = true,
				g = true,
			},
		},
	}
end

function M.setup()
	local group = vim.api.nvim_create_augroup("MayonWhichKeyPalette", { clear = true })
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		callback = vim.schedule_wrap(apply_highlights),
	})
	require("which-key").setup(M.config())
	apply_highlights()
	vim.schedule(apply_highlights)
	install_title()
end

function M.show_all()
	local ok, which_key = pcall(require, "which-key")
	if not ok then
		return false
	end
	which_key.show({ keys = "<leader>", mode = "n", delay = 0 })
	return true
end

return M
