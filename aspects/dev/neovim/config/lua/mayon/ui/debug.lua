local M = {}

local function highlights()
	local c = require("mayon.generated").palette
	local set = function(name, value)
		vim.api.nvim_set_hl(0, name, value)
	end
	set("DapBreakpoint", { fg = c.red })
	set("DapBreakpointCondition", { fg = c.orange })
	set("DapLogPoint", { fg = c.cyan })
	set("DapStopped", { fg = c.green })
	set("DapStoppedLine", { underline = true, sp = c.green })
	set("DapBreakpointRejected", { fg = c.muted })
	set("NvimDapVirtualText", { fg = c.muted, italic = true })
	set("NvimDapVirtualTextChanged", { fg = c.blue, italic = true })
	set("NvimDapVirtualTextError", { fg = c.orange, italic = true })
	set("NvimDapViewTab", { fg = c.muted, bg = c.bg })
	set("NvimDapViewTabSelected", { fg = c.fg, bg = c.bg, underline = true, sp = c.blue })
	set("NvimDapViewTabFill", { bg = c.bg })
	set("NvimDapViewFrameCurrent", { fg = c.blue, underline = true })
	set("NvimDapViewWatchUpdated", { fg = c.cyan })
end

function M.setup()
	local loader = require("mayon.config.loader")
	loader.pack("nvim-dap-view")
	loader.pack("nvim-dap-virtual-text")
	require("dap-view").setup({
		auto_toggle = true,
		windows = { position = "below", size = 12 },
		winbar = {
			sections = { "scopes", "watches", "breakpoints", "threads", "repl", "console" },
			default_section = "scopes",
			controls = { enabled = false },
			-- dap-view's native threads section already renders the stack and
			-- focuses a frame on <CR>; just relabel it for the embedded audience.
			base_sections = {
				scopes = { label = "Variables", keymap = "V" },
				threads = { label = "Stack", keymap = "S" },
			},
		},
		help = { border = require("mayon.util").border },
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
	dap.listeners.after.stackTrace.mayon_stack = function()
		-- Snacks expires its statuscolumn cache every 50 ms without requesting a
		-- redraw. A newly placed stopped sign otherwise waits for the next key.
		vim.defer_fn(function()
			vim.cmd.redraw()
		end, 60)
	end
end
return M
