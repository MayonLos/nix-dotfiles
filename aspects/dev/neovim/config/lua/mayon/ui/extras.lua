-- Window-local surfaces for built-in buffers and secondary plugin views.
local M = {}

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

local function add_window_highlights(win)
	local entries = {}
	local mapped = {}
	for entry in vim.wo[win].winhighlight:gmatch("[^,]+") do
		local source = entry:match("^([^:]+):")
		-- style=minimal adds EndOfBuffer: with an empty target. That clears
		-- its color instead of inheriting a plugin's floating namespace.
		if not (source == "EndOfBuffer" and entry:match("^EndOfBuffer:%s*$")) then
			if source then
				mapped[source] = true
			end
			entries[#entries + 1] = entry
		end
	end
	for _, entry in ipairs({
		"Normal:NormalFloat",
		"NormalNC:NormalFloat",
		"EndOfBuffer:NormalFloat",
		"FloatBorder:FloatBorder",
		"FloatTitle:FloatTitle",
	}) do
		local source = entry:match("^([^:]+):")
		if not mapped[source] then
			entries[#entries + 1] = entry
		end
	end
	vim.wo[win].winhighlight = table.concat(entries, ",")
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
	if virtual_width(win) then
		return
	end
	vim.wo[win].winhighlight =
		"Normal:NormalFloat,NormalNC:NormalFloat,WinBar:MayonPanelTitle,WinSeparator:FloatBorder,CursorLine:PmenuSel"
	-- Neovim 0.12 ui2 represents command/message surfaces with oversized hidden
	-- windows. A window-local winbar asks the TUI to lay out that virtual width
	-- and raises E36; keep its colors, but leave the synthetic surface alone.
	local ft = vim.bo[vim.api.nvim_win_get_buf(win)].filetype
	local ui2_surface = ft == "cmd" or ft == "msg" or ft == "dialog" or ft == "pager"
	if title and not ui2_surface and not virtual_width(win) and vim.api.nvim_win_get_width(win) <= vim.o.columns then
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
	if not config.border or config.border == "none" then
		config.border = "rounded"
	end
	if title_is_empty(config.title) and ft ~= "snacks_terminal" then
		config.title = " " .. surface_title(buf, title) .. " "
	end
	-- Keep native/plugin floats visually quiet and centered like the LSP popups.
	-- A little whitespace in the title itself prevents it touching the edge glyphs.
	config.title_pos = "center"
	pcall(vim.api.nvim_win_set_config, win, config)
	add_window_highlights(win)
end

function M.searchcount()
	if vim.v.hlsearch == 0 or vim.fn.getreg("/") == "" then
		return ""
	end
	local ok, count = pcall(vim.fn.searchcount, { recompute = 0, maxcount = 9999 })
	if not ok or not count or count.total == 0 then
		return ""
	end
	return ("[%d/%d]"):format(count.current or 0, count.total)
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
