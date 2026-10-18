-- Ported from a9d5614:nixvim/plugins/appearance/heirline.nix.
local M = {}

-- Presentation filtering never deletes a buffer or hides unsaved scratch work.
function M.buffers()
	local result = {}
	for _, info in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
		local buf = info.bufnr
		local empty = vim.api.nvim_buf_get_name(buf) == ""
			and vim.bo[buf].buftype == ""
			and not vim.bo[buf].modified
			and vim.api.nvim_buf_is_loaded(buf)
			and vim.api.nvim_buf_line_count(buf) == 1
			and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
		if not empty then
			result[#result + 1] = buf
		end
	end
	return result
end

function M.select(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	local function document_window(win)
		local bt = vim.bo[vim.api.nvim_win_get_buf(win)].buftype
		return vim.api.nvim_win_get_config(win).relative == "" and (bt == "" or bt == "acwrite")
	end
	local win = vim.api.nvim_get_current_win()
	if not document_window(win) then
		win = nil
		for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			if document_window(candidate) then
				win = candidate
				break
			end
		end
		if not win then
			vim.cmd("botright vnew")
			win = vim.api.nvim_get_current_win()
		end
	end
	vim.api.nvim_win_set_buf(win, buf)
	vim.api.nvim_set_current_win(win)
end

function M.build(text)
	local utils = require("heirline.utils")
	local Space = { provider = " " }
	local TablineFileIcon = {
		init = function(self)
			local ext = vim.fn.fnamemodify(self.filename, ":e")
			self.icon, self.icon_color =
				require("nvim-web-devicons").get_icon_color(self.filename, ext, { default = true })
		end,
		provider = function(self)
			return self.icon and (self.icon .. " ")
		end,
		hl = function(self)
			return { fg = self.icon_color }
		end,
	}

	local tabline_names, tabline_names_dirty = {}, true
	-- Resolve duplicate basenames only when the listed buffers or their paths change.
	local function buffer_path_parts(filename)
		return vim.split(vim.fn.fnamemodify(filename, ":~:."), "/", { trimempty = true })
	end
	local function refresh_tabline_names()
		if not tabline_names_dirty then
			return
		end

		local buffers, basename_counts = {}, {}
		for _, bufnr in ipairs(M.buffers()) do
			local filename = vim.api.nvim_buf_get_name(bufnr)
			local parts = filename == "" and {} or buffer_path_parts(filename)
			local basename = parts[#parts] or "[No Name]"
			buffers[#buffers + 1] = { bufnr = bufnr, parts = parts, basename = basename }
			basename_counts[basename] = (basename_counts[basename] or 0) + 1
		end

		local suffix_counts = {}
		for _, buffer in ipairs(buffers) do
			local suffix = ""
			for index = #buffer.parts, 1, -1 do
				suffix = suffix == "" and buffer.parts[index] or (buffer.parts[index] .. "/" .. suffix)
				suffix_counts[suffix] = (suffix_counts[suffix] or 0) + 1
			end
		end

		tabline_names = {}
		for _, buffer in ipairs(buffers) do
			local label = buffer.basename
			if basename_counts[label] > 1 then
				if #buffer.parts == 0 then
					label = label .. " #" .. buffer.bufnr
				else
					local suffix = buffer.basename
					for index = #buffer.parts - 1, 1, -1 do
						suffix = buffer.parts[index] .. "/" .. suffix
						label = suffix
						if suffix_counts[suffix] == 1 then
							break
						end
					end
					if suffix_counts[label] ~= 1 then
						label = label .. " #" .. buffer.bufnr
					end
				end
			end
			tabline_names[buffer.bufnr] = {
				label = label,
				duplicate = basename_counts[buffer.basename] > 1,
			}
		end
		tabline_names_dirty = false
	end
	vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete", "BufFilePost", "DirChanged", "BufModifiedSet" }, {
		group = vim.api.nvim_create_augroup("HeirlineBufferNames", { clear = true }),
		callback = function()
			tabline_names_dirty = true
		end,
	})
	vim.api.nvim_create_autocmd("OptionSet", {
		group = "HeirlineBufferNames",
		pattern = "buflisted",
		callback = function()
			tabline_names_dirty = true
		end,
	})

	local TablineFileName = {
		provider = function(self)
			local name = vim.fn.fnamemodify(self.filename, ":t")
			local buffer_name = tabline_names[self.bufnr]
			local width = math.max(1, math.min(28, vim.o.columns - 14))
			local label = buffer_name and buffer_name.label or (name == "" and "[No Name]" or name)
			if buffer_name and buffer_name.duplicate and vim.fn.strdisplaywidth(label) > width then
				local suffix = " #" .. self.bufnr
				return text(label, math.max(1, width - #suffix)) .. suffix
			end
			return text(label, width)
		end,
		hl = function(self)
			return { bold = self.is_active or self.is_visible }
		end,
	}

	local TablineFileFlags = {
		{
			condition = function(self)
				return vim.api.nvim_get_option_value("modified", { buf = self.bufnr })
			end,
			provider = " ●",
			hl = { fg = "green" },
		},
		{
			condition = function(self)
				return not vim.api.nvim_get_option_value("modifiable", { buf = self.bufnr })
					or vim.api.nvim_get_option_value("readonly", { buf = self.bufnr })
			end,
			provider = " 󰌾",
			hl = { fg = "orange" },
		},
	}

	local function close_buffer(bufnr)
		require("snacks").bufdelete({ buf = bufnr })
		vim.cmd.redrawtabline()
	end

	local TablineFileNameBlock = {
		init = function(self)
			self.filename = vim.api.nvim_buf_get_name(self.bufnr)
		end,
		hl = function(self)
			return self.is_active and "TabLineSel" or "TabLine"
		end,
		on_click = {
			callback = function(_, minwid, _, button)
				if button == "m" then
					vim.schedule(function()
						close_buffer(minwid)
					end)
				elseif button == "l" then
					vim.schedule(function()
						M.select(minwid)
					end)
				end
			end,
			minwid = function(self)
				return self.bufnr
			end,
			name = "heirline_tabline_buffer_callback",
		},
		{ provider = " " },
		TablineFileIcon,
		TablineFileName,
		TablineFileFlags,
	}

	local TablineCloseButton = {
		{ provider = " " },
		{
			provider = "×",
			hl = { fg = "gray" },
			on_click = {
				callback = function(_, minwid)
					vim.schedule(function()
						close_buffer(minwid)
					end)
				end,
				minwid = function(self)
					return self.bufnr
				end,
				name = "heirline_tabline_close_buffer_callback",
			},
		},
	}

	local TablineBufferBlock = {
		hl = function(self)
			return self.is_active and "TabLineSel" or "TabLine"
		end,
		TablineFileNameBlock,
		TablineCloseButton,
		Space,
	}

	local BufferList = utils.make_buflist(
		TablineBufferBlock,
		{ provider = " ‹ ", hl = { fg = "gray" } },
		{ provider = " › ", hl = { fg = "gray" } },
		M.buffers,
		false
	)
	local make_buflist_init = BufferList.init
	BufferList.init = function(self)
		refresh_tabline_names()
		make_buflist_init(self)
	end

	local Tabpage = {
		provider = function(self)
			return "%" .. self.tabnr .. "T " .. self.tabnr .. " %T"
		end,
		hl = function(self)
			return self.is_active and "TabLineSel" or "TabLine"
		end,
	}
	local TabpageClose = { provider = "%999X × %X", hl = "TabLine" }
	local TabPages = {
		condition = function()
			return #vim.api.nvim_list_tabpages() >= 2
		end,
		{ provider = "%=" },
		utils.make_tablist(Tabpage),
		TabpageClose,
	}

	local TabLine = { hl = "TabLineFill", BufferList, TabPages }

	return TabLine
end

return M
