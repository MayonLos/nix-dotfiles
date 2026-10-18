-- Explicit Kitty-graphics previews. Document and formula rendering stay off.
local M = {}

local image_extensions = {
	avif = true,
	bmp = true,
	gif = true,
	heic = true,
	heif = true,
	jpeg = true,
	jpg = true,
	jxl = true,
	png = true,
	tif = true,
	tiff = true,
	webp = true,
}

local active
local namespace = vim.api.nvim_create_namespace("mayon.image.preview")

local function notify(message, level)
	vim.notify(message, level or vim.log.levels.INFO, { title = "Image preview" })
end

local function current_path(path)
	if path and path ~= "" then
		return vim.fn.fnamemodify(path, ":p")
	end
	local name = vim.api.nvim_buf_get_name(0)
	return name ~= "" and vim.fn.fnamemodify(name, ":p") or nil
end

local function fallback(path, reason)
	if reason then
		notify(reason .. "; opening with the system viewer", vim.log.levels.WARN)
	end
	if vim.ui.open then
		vim.ui.open(path)
	else
		vim.fn.jobstart({ "xdg-open", path }, { detach = true })
	end
end

local function tmux_passthrough()
	if not vim.env.TMUX or vim.env.TMUX == "" then
		return true
	end
	local tmux = vim.fn.exepath("tmux")
	if tmux == "" then
		return false
	end
	local argv = { tmux, "show-option", "-Apqv" }
	if vim.env.TMUX_PANE and vim.env.TMUX_PANE ~= "" then
		vim.list_extend(argv, { "-t", vim.env.TMUX_PANE })
	end
	argv[#argv + 1] = "allow-passthrough"
	local result = vim.system(argv, { text = true }):wait()
	local setting = (result.stdout or ""):gsub("[%s\r\n]+$", "")
	return result.code == 0 and (setting == "on" or setting == "all")
end

local function kitty_context()
	local terminal = vim.env.TERM or ""
	local is_kitty = vim.env.KITTY_WINDOW_ID ~= nil or terminal:match("kitty") ~= nil
	if not is_kitty then
		return false, "The current terminal is not Kitty"
	end
	if not tmux_passthrough() then
		return false, "tmux allow-passthrough is not enabled"
	end
	return true
end

local function kitty_escape(sequence)
	return "\27Ptmux;" .. sequence:gsub("\27", "\27\27") .. "\27\\"
end

local function graphics_sequences(raw)
	local result = {}
	for sequence in raw:gmatch("\27_G.-\27\\") do
		result[#result + 1] = sequence
	end
	return result
end

local function ansi_color(raw, code)
	local color
	for sgr in raw:gmatch("\27%[([%d:;]*)m") do
		for part in sgr:gmatch("[^;]+") do
			local values = vim.split(part, ":", { plain = true })
			if tonumber(values[1]) == code and tonumber(values[2]) == 2 then
				local offset = #values == 5 and 3 or 2
				local red, green, blue =
					tonumber(values[offset]), tonumber(values[offset + 1]), tonumber(values[offset + 2])
				if red and green and blue then
					color = string.format("#%02x%02x%02x", red, green, blue)
				end
			end
		end
	end
	return color
end

local function placeholder_data(raw)
	local foreground = ansi_color(raw, 38)
	local underline = ansi_color(raw, 58)
	local text = raw:gsub("\27_G.-\27\\", "")
	text = text:gsub("\27%[[0-?]*[ -/]*[@-~]", "")
	text = text:gsub("\27[78]", ""):gsub("\r", "")
	text = text:gsub("\27%][^\7]*\7", "")
	local lines = vim.split(text, "\n", { plain = true })
	while #lines > 0 and lines[#lines] == "" do
		table.remove(lines)
	end
	return #lines > 0 and lines or { "" }, foreground, underline
end

local function remove_preview(state)
	if active ~= state then
		return
	end
	active = nil
	if state.image_id then
		local ok, tty = pcall(vim.uv.fs_open, "/dev/tty", "w", 384)
		if ok and tty then
			local command = string.format("\27_Ga=d,d=I,i=%s,q=2\27\\", state.image_id)
			if vim.env.TMUX and vim.env.TMUX ~= "" then
				command = kitty_escape(command)
			end
			vim.uv.fs_write(tty, command, -1)
			vim.uv.fs_close(tty)
		end
	end
	if state.process_handle then
		pcall(state.process_handle.kill, state.process_handle, 15)
	end
	if state.augroup then
		pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
	end
	if state.win and vim.api.nvim_win_is_valid(state.win) then
		vim.api.nvim_win_close(state.win, true)
	end
	if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
		pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
	end
	if state.cleanup then
		vim.uv.fs_unlink(state.cleanup)
	end
end

local function send_to_terminal(state, sequences)
	local ok, fd = pcall(vim.uv.fs_open, "/dev/tty", "w", 384)
	if not ok or not fd then
		return false
	end
	local parts = { "\27" .. "7" }
	for _, sequence in ipairs(sequences) do
		parts[#parts + 1] = vim.env.TMUX and vim.env.TMUX ~= "" and kitty_escape(sequence) or sequence
	end
	parts[#parts + 1] = "\27" .. "8"
	local wrote = pcall(vim.uv.fs_write, fd, table.concat(parts), -1)
	vim.uv.fs_close(fd)
	return wrote
end

local function open_float(path, source_buf)
	local source_win = vim.api.nvim_get_current_win()
	local width = vim.api.nvim_win_get_width(source_win)
	local height = vim.api.nvim_win_get_height(source_win)
	local position = vim.api.nvim_win_get_position(source_win)
	local row, col = position[1], position[2]
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Preparing image preview…" })
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		style = "minimal",
		focusable = true,
		row = row,
		col = col,
		width = math.max(1, width),
		height = math.max(1, height),
		zindex = 80,
	})
	vim.wo[win].wrap = false
	vim.wo[win].number = false
	vim.wo[win].relativenumber = false
	vim.wo[win].signcolumn = "no"
	local state = { buf = buf, win = win, source_buf = source_buf, path = path }
	active = state
	vim.keymap.set("n", "q", function()
		remove_preview(state)
	end, { buffer = buf, nowait = true, silent = true, desc = "Close image preview" })
	vim.keymap.set("n", "<Esc>", function()
		remove_preview(state)
	end, { buffer = buf, nowait = true, silent = true, desc = "Close image preview" })
	return state, width, height
end

local function render_kitty(path, source_buf, cleanup, fallback_path)
	local open_path = fallback_path or path
	local kitten = vim.fn.exepath("kitten")
	if kitten == "" then
		if cleanup then
			vim.uv.fs_unlink(cleanup)
		end
		fallback(open_path, "Kitty kitten is unavailable")
		return false
	end
	local context, reason = kitty_context()
	if not context then
		if cleanup then
			vim.uv.fs_unlink(cleanup)
		end
		fallback(open_path, reason)
		return false
	end
	local state, width, height = open_float(path, source_buf)
	state.cleanup = cleanup
	local position = vim.api.nvim_win_get_position(state.win)
	local row, col = position[1], position[2]
	local columns, rows = vim.o.columns, vim.o.lines
	local passthrough = "none" -- protocol is wrapped below after Kitty emits it
	local command = {
		kitten,
		"icat",
		"--stdin",
		"no",
		"--unicode-placeholder",
		"--passthrough",
		passthrough,
		"--scale-up",
		"--place",
		string.format("%dx%d@%dx%d", width, height, col, row),
		"--use-window-size",
		string.format("%d,%d,%d,%d", columns, rows, columns * 8, rows * 16),
		"--transfer-mode",
		"stream",
		path,
	}
	local ok, process = pcall(vim.system, command, { text = true }, function(result)
		vim.schedule(function()
			if active ~= state then
				return
			end
			if result.code ~= 0 then
				remove_preview(state)
				fallback(open_path, "Kitty could not render this image")
				return
			end
			local raw = result.stdout or ""
			local sequences = graphics_sequences(raw)
			if #sequences == 0 then
				remove_preview(state)
				fallback(open_path, "Kitty returned no graphics protocol data")
				return
			end
			local id = sequences[1]:match("[,;]i=(%d+)[,;]")
			state.image_id = id
			-- Create the virtual placement before the terminal sees placeholder glyphs.
			if not send_to_terminal(state, sequences) then
				remove_preview(state)
				fallback(open_path, "Could not access the current terminal")
				return
			end
			local lines, foreground, underline = placeholder_data(raw)
			if foreground then
				vim.api.nvim_set_hl(0, "MayonImagePlacement", {
					fg = foreground,
					sp = underline,
					underline = underline ~= nil,
					nocombine = true,
				})
			end
			vim.bo[state.buf].modifiable = true
			vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
			vim.bo[state.buf].modifiable = false
			if foreground then
				for line = 0, #lines - 1 do
					vim.api.nvim_buf_add_highlight(state.buf, namespace, "MayonImagePlacement", line, 0, -1)
				end
			end
			vim.cmd.redraw()
		end)
	end)
	if not ok or not process then
		remove_preview(state)
		fallback(open_path, "Could not start Kitty image renderer")
		return false
	end
	state.process_handle = process
	return true
end

local function preview_pdf(path, source_buf)
	local magick = vim.fn.exepath("magick")
	if magick == "" then
		fallback(path, "ImageMagick is unavailable for PDF preview")
		return false
	end
	local output = vim.fn.tempname() .. ".png"
	local command =
		{ magick, "-density", "144", path .. "[0]", "-background", "white", "-alpha", "remove", "-trim", output }
	local state = { path = path, source_buf = source_buf, cleanup = output }
	active = state
	local ok, process = pcall(vim.system, command, { text = true }, function(result)
		vim.schedule(function()
			if active ~= state then
				return
			end
			active = nil
			if state.augroup then
				pcall(vim.api.nvim_del_augroup_by_id, state.augroup)
			end
			if result.code ~= 0 or vim.fn.filereadable(output) ~= 1 then
				vim.uv.fs_unlink(output)
				fallback(path, "Could not render the first PDF page")
				return
			end
			render_kitty(output, source_buf, output, path)
		end)
	end)
	if not ok or not process then
		active = nil
		vim.uv.fs_unlink(output)
		fallback(path, "Could not start PDF conversion")
		return false
	end
	state.process_handle = process
	state.augroup = vim.api.nvim_create_augroup("MayonImagePdfConversion", { clear = true })
	vim.api.nvim_create_autocmd({ "WinLeave", "BufDelete", "VimLeavePre" }, {
		group = state.augroup,
		buffer = source_buf,
		callback = function()
			remove_preview(state)
		end,
	})
	return true
end

function M.open(path)
	if active then
		remove_preview(active)
	end
	path = current_path(path)
	if not path or vim.fn.filereadable(path) ~= 1 then
		notify("No readable image or PDF file", vim.log.levels.ERROR)
		return false
	end
	local extension = vim.fn.fnamemodify(path, ":e"):lower()
	if extension == "pdf" then
		return preview_pdf(path, vim.api.nvim_get_current_buf())
	end
	if not image_extensions[extension] then
		fallback(path, "Unsupported image format")
		return false
	end
	return render_kitty(path, vim.api.nvim_get_current_buf())
end

function M.setup()
	vim.api.nvim_create_user_command("ImagePreview", function(args)
		M.open(args.args ~= "" and args.args or nil)
	end, { nargs = "?", complete = "file", desc = "Preview an image or PDF in Kitty" })
	local patterns = {}
	for extension in pairs(image_extensions) do
		patterns[#patterns + 1] = "*." .. extension
		patterns[#patterns + 1] = "*." .. extension:upper()
	end
	local group = vim.api.nvim_create_augroup("MayonImagePreview", { clear = true })
	vim.api.nvim_create_autocmd("BufReadCmd", {
		group = group,
		pattern = patterns,
		callback = function(args)
			local buf = args.buf
			vim.bo[buf].buftype = "nofile"
			vim.bo[buf].bufhidden = "hide"
			vim.bo[buf].swapfile = false
			vim.bo[buf].filetype = "mayon-image-preview"
			vim.bo[buf].modifiable = true
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "Image preview is open in this window." })
			vim.bo[buf].modifiable = false
			M.open(args.file)
		end,
	})
	vim.api.nvim_create_autocmd("WinLeave", {
		group = group,
		callback = function()
			if active and active.win == vim.api.nvim_get_current_win() then
				remove_preview(active)
			end
		end,
	})
	vim.api.nvim_create_autocmd("WinClosed", {
		group = group,
		callback = function(args)
			if active and tonumber(args.match) == active.win then
				remove_preview(active)
			end
		end,
	})
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			if active then
				remove_preview(active)
			end
		end,
	})
end

return M
