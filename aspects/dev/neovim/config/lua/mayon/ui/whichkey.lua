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
			border = require("mayon.util").border,
			-- which-key resolves these per render (Layout.dim): fractions follow the
			-- current 'columns', so the popup stays centred after a resize.
			row = -1,
			col = 0.5,
			width = { min = 40, max = max_window_width },
			height = { min = 4, max = 10 },
			padding = { 0, 1 },
			title = true,
			title_pos = "center",
			wo = { winblend = 0 },
		},
		layout = {
			width = { min = 20, max = 27 },
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
