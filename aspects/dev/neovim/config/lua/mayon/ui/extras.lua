-- Window-local surfaces for built-in buffers and secondary plugin views.
-- Most of this module's work moved into util.winhl / theme / statusline;
-- what remains is the shared secondary-surface titles and the highlight-colors
-- option table that decorations.lua applies.
local M = {}
local util = require("mayon.util")

local titles = {
	oil = "Project",
	["grug-far"] = "Find · Replace",
	checkhealth = "Health",
	["codediff-explorer"] = "Git Review",
	help = "Help",
	man = "Manual",
	qf = "Problems",
	msg = "Messages",
	pager = "Pager",
	dialog = "Confirm",
}

local function escaped(value)
	return tostring(value or ""):gsub("%%", "%%%%")
end

local function surface_title(buf, fallback)
	local ft = buf and vim.bo[buf].filetype or ""
	local title = titles[ft] or fallback or ft:gsub("_", " ")
	local name = buf and vim.api.nvim_buf_get_name(buf) or ""
	local source = name ~= "" and vim.fn.fnamemodify(name, ":t") or ft
	if title == source or source == "" then
		return title:upper()
	end
	return title .. " · " .. source
end

local function title_is_empty(title)
	if type(title) == "string" then
		return title:match("^%s*$") ~= nil
	end
	if type(title) == "table" then
		local parts = {}
		for _, chunk in ipairs(title) do
			parts[#parts + 1] = type(chunk) == "table" and tostring(chunk[1] or "") or tostring(chunk)
		end
		return table.concat(parts):match("^%s*$") ~= nil
	end
	return title == nil or title == false
end

-- A float without a visible frame: no border, "none", or eight empty glyphs.
local function border_is_missing(border)
	if border == nil or border == "none" or border == "" then
		return true
	end
	if type(border) == "table" then
		for _, part in ipairs(border) do
			local glyph = type(part) == "table" and part[1] or part
			if glyph ~= "" then
				return false
			end
		end
		return true
	end
	return false
end

local function virtual_width(win)
	local width = vim.api.nvim_win_get_config(win).width
	return width ~= nil and width > vim.o.columns
end

function M.style(win, title)
	if not vim.api.nvim_win_is_valid(win) then
		return
	end
	-- Neovim 0.12 ui2 creates hidden command/message windows with a logical
	-- width larger than the screen, even though get_width() reports a clamp.
	-- Do not attach layout options to those internal windows.
	local virtual = virtual_width(win)
	if virtual then
		return
	end
	util.winhl(win, {
		Normal = "NormalFloat",
		NormalNC = "NormalFloat",
		WinBar = "MayonPanelTitle",
		WinSeparator = "FloatBorder",
		CursorLine = "PmenuSel",
	})
	-- Neovim 0.12 ui2 represents command/message surfaces with oversized hidden
	-- windows. A window-local winbar asks the TUI to lay out that virtual width
	-- and raises E36; keep its colors, but leave the synthetic surface alone.
	local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
	local ui2_surface = ft == "cmd" or ft == "msg" or ft == "dialog" or ft == "pager"
	if title and not ui2_surface and not virtual and vim.api.nvim_win_get_width(win) <= vim.o.columns then
		vim.wo[win].winbar = "%#MayonPanelTitle# " .. escaped(title) .. " %*"
	end
end

function M.style_float(win, title)
	if not vim.api.nvim_win_is_valid(win) then
		return
	end
	local config = vim.api.nvim_win_get_config(win)
	if
		config.relative == ""
		or virtual_width(win)
		or vim.api.nvim_win_get_width(win) > vim.o.columns
		or vim.w[win].snacks_win
	then
		return
	end
	local buf = vim.api.nvim_win_get_buf(win)
	local ft = vim.bo[buf].filetype
	if ft:match("^snacks_") or ft == "wk" then
		return
	end
	-- Fill in a frame only where the plugin left none; explicit borders stay.
	if border_is_missing(config.border) then
		config.border = util.border
	end
	if title_is_empty(config.title) then
		config.title = " " .. surface_title(buf, title) .. " "
	end
	-- Keep native/plugin floats visually quiet and centered like the LSP popups.
	config.title_pos = "center"
	pcall(vim.api.nvim_win_set_config, win, config)
	util.winhl(win, {
		Normal = "NormalFloat",
		NormalNC = "NormalFloat",
		EndOfBuffer = "NormalFloat",
		FloatBorder = "FloatBorder",
		FloatTitle = "FloatTitle",
	})
end

function M.color_options()
	return {
		render = "virtual",
		virtual_symbol = "■",
		virtual_symbol_position = "inline",
		virtual_symbol_suffix = " ",
		enable_hex = true,
		enable_short_hex = true,
		enable_rgb = true,
		enable_hsl = true,
		enable_var_usage = true,
		enable_named_colors = false,
		enable_tailwind = true,
		exclude_filetypes = { "bigfile", "checkhealth", "help", "snacks_dashboard", "snacks_picker_list" },
	}
end

function M.setup()
	vim.api.nvim_create_autocmd("FileType", {
		group = vim.api.nvim_create_augroup("MayonSecondarySurfaces", { clear = true }),
		pattern = {
			"oil",
			"grug-far",
			"checkhealth",
			"help",
			"man",
			"qf",
			"cmd",
			"msg",
			"pager",
			"dialog",
			"codediff-explorer",
		},
		callback = function(event)
			local ft = vim.bo[event.buf].filetype
			for _, win in ipairs(vim.fn.win_findbuf(event.buf)) do
				M.style(win, surface_title(event.buf, titles[ft]))
			end
		end,
	})
	vim.api.nvim_create_autocmd({ "WinNew", "WinEnter" }, {
		group = "MayonSecondarySurfaces",
		callback = function()
			local win = vim.api.nvim_get_current_win()
			vim.schedule(function()
				if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_config(win).relative ~= "" then
					M.style_float(win)
				end
			end)
		end,
	})
end

return M
