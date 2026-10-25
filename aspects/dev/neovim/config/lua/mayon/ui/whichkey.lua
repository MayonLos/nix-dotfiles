local M = {}

local function apply_highlights()
	local c = require("mayon.generated").palette
	vim.api.nvim_set_hl(0, "WhichKey", { fg = c.blue, bg = c.deep, bold = true })
	vim.api.nvim_set_hl(0, "WhichKeyDesc", { fg = c.fg, bg = c.deep })
	vim.api.nvim_set_hl(0, "WhichKeyGroup", { fg = c.muted, bg = c.deep })
	vim.api.nvim_set_hl(0, "WhichKeySeparator", { fg = c.muted, bg = c.deep })
	vim.api.nvim_set_hl(0, "WhichKeyTitle", { fg = c.muted, bg = c.deep, bold = true })
	vim.api.nvim_set_hl(0, "WhichKeyNormal", { fg = c.fg, bg = c.deep })
	local edge = require("mayon.ui.theme").float_edge()
	vim.api.nvim_set_hl(0, "WhichKeyBorder", { fg = edge, bg = c.deep })
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
	local render = view.show
	view.show = function(...)
		local width = math.max(16, math.floor((math.floor(vim.o.columns * 0.96) - 10) / 4))
		require("which-key.config").options.layout.width = { min = width, max = width }
		local result = render(...)
		local popup = view.view
		local win = popup and popup.win
		if win and vim.api.nvim_win_is_valid(win) then
			local buf = vim.api.nvim_win_get_buf(win)
			if vim.bo[buf].filetype == "wk" then
				spread_columns(win)
				vim.api.nvim_win_set_config(win, { title = " ␣ LEADER ", title_pos = "center" })
			end
		end
		return result
	end
end

function M.config()
	return {
		spec = {
			{ "<leader>f", group = "文件" },
			{ "<leader>r", group = "Run / 串口" },
			{ "<leader>d", group = "Debug" },
			{ "<leader>q", group = "关闭 / 重启" },
			{ "<leader>s", group = "搜索" },
			{ "<leader>g", group = "Git" },
			{ "<leader>c", group = "代码" },
			{ "<leader>a", group = "AI" },
			{ "<leader>x", group = "列表" },
			{ "<leader>u", group = "界面" },
			{ "<leader>t", group = "终端" },
			{ "<leader>p", group = "项目与会话" },
			{ "<leader>b", group = "缓冲区" },
			{ "<leader>l", group = "语言服务" },
			{ "<leader>m", group = "多光标", mode = { "n", "x" } },
			{ "<leader>n", group = "文档" },
		},
		icons = { mappings = false, colors = false, separator = " " },
		replace = { desc = { { "^%+", "+" } } },
		show_help = false,
		show_keys = false,
		win = {
			border = "rounded",
			row = -1,
			col = 0.02,
			width = 0.96,
			height = { min = 4, max = 10 },
			padding = { 0, 1 },
			title = " ␣ LEADER ",
			title_pos = "center",
			wo = { winblend = 0 },
		},
		layout = {
			width = {
				min = math.max(16, math.floor((math.floor(vim.o.columns * 0.96) - 10) / 4)),
				max = math.max(16, math.floor((math.floor(vim.o.columns * 0.96) - 10) / 4)),
			},
			spacing = 2,
		},
	}
end

function M.setup()
	apply_highlights()
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("MayonWhichKeyPalette", { clear = true }),
		callback = apply_highlights,
	})
	require("which-key").setup(M.config())
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
