local M = {}
local stack_buffer
local frames = {}

local function highlights()
	local c = require("mayon.generated").palette
	local set = function(name, value)
		vim.api.nvim_set_hl(0, name, value)
	end
	set("DapBreakpoint", { fg = c.red })
	set("DapBreakpointCondition", { fg = c.orange })
	set("DapLogPoint", { fg = c.cyan })
	set("DapStopped", { fg = c.green, bold = true })
	set("DapStoppedLine", { underline = true, sp = c.green })
	set("DapBreakpointRejected", { fg = c.muted })
	set("NvimDapVirtualText", { fg = c.muted, italic = true })
	set("NvimDapVirtualTextChanged", { fg = c.cyan, italic = true })
	set("NvimDapVirtualTextError", { fg = c.orange, italic = true })
	set("NvimDapViewTab", { fg = c.muted, bg = c.deep })
	set("NvimDapViewTabSelected", { fg = c.fg, bg = c.deep, underline = true, sp = c.blue })
	set("NvimDapViewTabFill", { bg = c.deep })
	set("NvimDapViewFrameCurrent", { fg = c.green, underline = true })
	set("NvimDapViewWatchUpdated", { fg = c.cyan })
end

local function stack_buf()
	if not stack_buffer or not vim.api.nvim_buf_is_valid(stack_buffer) then
		stack_buffer = vim.api.nvim_create_buf(false, true)
		vim.bo[stack_buffer].filetype = "dap-view"
		vim.bo[stack_buffer].bufhidden = "hide"
		vim.keymap.set("n", "<CR>", function()
			local frame = frames[vim.api.nvim_win_get_cursor(0)[1]]
			if frame and frame.source and frame.source.path then
				local dap = require("dap")
				local session = dap.session()
				local current = session and session.current_frame
				local index
				for i, f in ipairs(frames) do
					if current and f.id == current.id then
						index = i
					end
				end
				local target = vim.api.nvim_win_get_cursor(0)[1]
				if index then
					for _ = 1, math.abs(target - index) do
						if target > index then
							dap.up()
						else
							dap.down()
						end
					end
				end
				dap.focus_frame()
			end
		end, { buffer = stack_buffer, desc = "Focus stack frame" })
	end
	return stack_buffer
end

local function render_stack()
	local buf = stack_buf()
	local session = require("dap").session()
	local thread = session and session.threads[session.stopped_thread_id]
	frames = thread and thread.frames or {}
	local lines = {}
	for i, f in ipairs(frames) do
		lines[i] = ("%s %s  %s:%s"):format(
			session.current_frame and session.current_frame.id == f.id and "▸" or " ",
			f.name,
			f.source and (f.source.path or f.source.name) or "",
			f.line or ""
		)
	end
	if #lines == 0 then
		lines = { "No stopped stack" }
	end
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.bo[buf].modifiable = false
	local win = require("dap-view.state").winnr
	if win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == buf then
		vim.wo[win].number = false
		vim.wo[win].relativenumber = false
		vim.wo[win].signcolumn = "no"
	end
end

function M.setup()
	local loader = require("mayon.config.loader")
	loader.pack("nvim-dap-view")
	loader.pack("nvim-dap-virtual-text")
	require("dap-view").setup({
		auto_toggle = true,
		windows = { position = "below", size = 12 },
		winbar = {
			sections = { "scopes", "watches", "breakpoints", "stack", "threads", "repl", "console" },
			default_section = "scopes",
			controls = { enabled = false },
			base_sections = { scopes = { label = "Variables", keymap = "V" } },
			custom_sections = { stack = { label = "Stack", keymap = "S", buffer = stack_buf, action = render_stack } },
		},
		help = { border = "rounded" },
	})
	require("nvim-dap-virtual-text").setup({
		commented = true,
		highlight_changed_variables = true,
		highlight_new_as_changed = false,
		show_stop_reason = false,
		only_first_definition = true,
		virt_text_pos = "eol",
		display_callback = function(variable)
			return " " .. variable.name .. " = " .. variable.value:gsub("%s+", " "):sub(1, 80)
		end,
	})
	for name, text in pairs({
		DapBreakpoint = "●",
		DapBreakpointCondition = "◆",
		DapLogPoint = "◇",
		DapStopped = "▸",
		DapBreakpointRejected = "○",
	}) do
		vim.fn.sign_define(
			name,
			{ text = text, texthl = name, linehl = name == "DapStopped" and "DapStoppedLine" or "" }
		)
	end
	highlights()
	vim.api.nvim_create_autocmd(
		"ColorScheme",
		{ group = vim.api.nvim_create_augroup("MayonDebugPalette", { clear = true }), callback = highlights }
	)
	local dap = require("dap")
	dap.listeners.after.event_stopped.mayon_stack = function()
		vim.schedule(render_stack)
	end
	dap.listeners.after.scopes.mayon_stack = function()
		vim.schedule(render_stack)
	end
	dap.listeners.after.stackTrace.mayon_stack = function()
		vim.schedule(render_stack)
		-- Snacks expires its statuscolumn cache every 50 ms without requesting a
		-- redraw. A newly placed stopped sign otherwise waits for the next key.
		vim.defer_fn(function()
			vim.cmd.redraw()
		end, 60)
	end
end
return M
