-- Project identity and document tabs; Heirline owns paging and click dispatch.
local M = {}
local active_documents = {}

-- Focus may move to a sidebar or prompt without changing the active document.
function M.active_buffer()
	local tab, buf = vim.api.nvim_get_current_tabpage(), vim.api.nvim_get_current_buf()
	local function document(candidate)
		return candidate
			and vim.api.nvim_buf_is_valid(candidate)
			and vim.bo[candidate].buflisted
			and (vim.bo[candidate].buftype == "" or vim.bo[candidate].buftype == "acwrite")
	end
	if document(buf) then
		active_documents[tab] = buf
	elseif not document(active_documents[tab]) then
		active_documents[tab] = nil
		for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tab)) do
			local visible = vim.api.nvim_win_get_buf(win)
			if document(visible) then
				active_documents[tab] = visible
				break
			end
		end
	end
	return active_documents[tab]
end

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

-- Align document tabs with the editor when Snacks owns a real left split.
-- Inspect the split, not its floating input/list children or a fixed column count.
function M.sidebar_width()
	for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		if
			vim.api.nvim_win_get_config(win).relative == ""
			and vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "snacks_layout_box"
			and vim.api.nvim_win_get_position(win)[2] == 0
		then
			local width = vim.api.nvim_win_get_width(win)
			if width < vim.o.columns then
				return width + 1
			end
		end
		if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "snacks_picker_list" then
			local position = vim.api.nvim_win_get_position(win)
			local width = vim.api.nvim_win_get_width(win)
			if position[2] == 0 and width < vim.o.columns then
				return width + 1
			end
		end
	end
	return 0
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

function M.build()
	local utils = require("heirline.utils")
	local text = require("mayon.ui.text")
	local tabline_names, tabline_names_dirty = {}, true
	local buffer_group = vim.api.nvim_create_augroup("HeirlineBufferNames", { clear = true })
	local function invalidate_buffers()
		tabline_names_dirty = true
	end
	vim.api.nvim_create_autocmd({
		"BufAdd",
		"BufDelete",
		"BufEnter",
		"BufFilePost",
		"BufModifiedSet",
		"BufUnload",
		"DiagnosticChanged",
		"DirChanged",
		"TextChanged",
		"TextChangedI",
	}, { group = buffer_group, callback = invalidate_buffers })
	vim.api.nvim_create_autocmd("OptionSet", {
		group = buffer_group,
		pattern = "buflisted",
		callback = invalidate_buffers,
	})
	local focus_group = vim.api.nvim_create_augroup("MayonDocumentFocus", { clear = true })
	vim.api.nvim_create_autocmd({ "BufEnter", "WinEnter" }, {
		group = focus_group,
		callback = function()
			M.active_buffer()
		end,
	})
	vim.api.nvim_create_autocmd("TabClosed", {
		group = focus_group,
		callback = function()
			for tab in pairs(active_documents) do
				if not vim.api.nvim_tabpage_is_valid(tab) then
					active_documents[tab] = nil
				end
			end
		end,
	})
	M.active_buffer()
	local Space = { provider = " " }
	local function tab_highlight(self)
		return self.is_active and "TabLineSel" or "TabLine"
	end

	-- Resolve duplicate basenames only when the listed buffers or their paths change.
	local function buffer_path_parts(filename)
		return vim.split(vim.fn.fnamemodify(filename, ":~:."), "/", { trimempty = true })
	end
	local tabline_names_signature
	local function refresh_tabline_names(buflist)
		local signature, filenames = {}, {}
		for _, bufnr in ipairs(buflist) do
			local filename = vim.api.nvim_buf_get_name(bufnr)
			signature[#signature + 1] = bufnr .. "\0" .. filename
			filenames[bufnr] = filename
		end
		local current_signature = table.concat(signature, "\1")
		if not tabline_names_dirty and current_signature == tabline_names_signature then
			return
		end
		local buffers, basename_counts = {}, {}
		for _, bufnr in ipairs(buflist) do
			local filename = filenames[bufnr]
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
		tabline_names_signature = current_signature
	end
	local TablineFileName = {
		provider = function(self)
			local name = vim.fn.fnamemodify(self.filename, ":t")
			local buffer_name = tabline_names[self.bufnr]
			local width = math.max(8, math.min(28, math.floor((vim.o.columns - M.sidebar_width() - 16) / 3)))
			local label = buffer_name and buffer_name.label or (name == "" and "[No Name]" or name)
			if buffer_name and buffer_name.duplicate and vim.fn.strwidth(label) > width then
				local suffix = " #" .. self.bufnr
				return text.fit(label, math.max(1, width - vim.fn.strwidth(suffix))) .. suffix
			end
			return text.fit(label, width)
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
			hl = { fg = "orange" },
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
	local TablineFileIcon = {
		init = function(self)
			self.file_icon, self.file_icon_hl = require("mayon.ui.icons").get(self.filename)
		end,
		provider = function(self)
			return self.file_icon
		end,
		hl = function(self)
			return self.file_icon_hl
		end,
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
			return tab_highlight(self)
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

	-- Underline the active label: a terminal cell cannot draw a 2px top rule.
	local TablineBufferBlock = {
		hl = function(self)
			return tab_highlight(self)
		end,
		TablineFileNameBlock,
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
		make_buflist_init(self)
		refresh_tabline_names(self.buffers)
		local active = M.active_buffer()
		self.active_child = false
		for index, bufnr in ipairs(self.buffers) do
			self[index].is_active = bufnr == active
			if bufnr == active then
				self.active_child = index
			end
		end
	end

	local Tabpage = {
		provider = function(self)
			return "%" .. self.tabnr .. "T " .. self.tabnr .. " %T"
		end,
		hl = function(self)
			return tab_highlight(self)
		end,
	}
	local TabPages = {
		condition = function()
			return #vim.api.nvim_list_tabpages() >= 2
		end,
		{ provider = "%=" },
		utils.make_tablist(Tabpage),
	}

	local Project = {
		condition = function()
			return vim.o.columns >= 90 or M.sidebar_width() > 0
		end,
		provider = function()
			local cwd = vim.fn.getcwd()
			local file = vim.api.nvim_buf_get_name(M.active_buffer() or 0)
			local root = vim.fs.root(file ~= "" and file or cwd, { ".git" }) or cwd
			local name = vim.fn.fnamemodify(root, ":t")
			local offset = M.sidebar_width()
			if offset > 0 then
				return string.rep(" ", offset - 1)
			end
			return "  " .. text.fit(name, math.min(20, math.floor(vim.o.columns * 0.14))) .. "  "
		end,
		hl = "MayonProject",
	}
	local TabLine = {
		condition = function()
			return vim.bo.filetype ~= "snacks_dashboard"
		end,
		hl = "TabLineFill",
		Project,
		Space,
		BufferList,
		{ provider = "%=" },
		TabPages,
	}

	return TabLine
end

return M
