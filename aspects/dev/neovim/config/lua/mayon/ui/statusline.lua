-- A quiet workspace rail: editing mode, location, attention, then cursor position.
local M = {}
local ready = false
local codecompanion_requests = {}

local function ai_status()
	local completion = package.loaded["mayon.features.ai_completion"]
	local provider = completion and completion.provider or "copilot"
	local pending = completion and completion.pending or 0
	local copilot_pending = 0
	if provider == "copilot" then
		for _, client in ipairs(vim.lsp.get_clients({ name = "copilot" })) do
			for _, request in pairs(client.requests or {}) do
				if request.type == "pending" and request.method == "textDocument/inlineCompletion" then
					copilot_pending = copilot_pending + 1
				end
			end
		end
	end
	local requests = 0
	for _ in pairs(codecompanion_requests) do
		requests = requests + 1
	end
	local companion_loaded = package.loaded.codecompanion ~= nil
	local companion_command = vim.fn.exists(":CodeCompanion") == 2
	local completion_pending = provider == "deepseek" and pending or provider == "copilot" and copilot_pending or 0
	return {
		provider = provider,
		completion_enabled = provider ~= "off",
		completion_generating = provider ~= "off"
			and ((completion and completion.busy == true) or completion_pending > 0),
		completion_pending = completion_pending,
		codecompanion_enabled = companion_loaded or companion_command,
		codecompanion_generating = requests > 0,
		codecompanion_requests = requests,
	}
end

-- Public status data is deliberately read-only so state transitions can be
-- checked without starting either AI provider.
function M.ai_status()
	return ai_status()
end

function M.setup()
	if ready then
		return
	end
	ready = true
	require("mayon.config.loader").pack("heirline.nvim")
	local heirline = require("heirline")
	local conditions = require("heirline.conditions")
	local utils = require("heirline.utils")
	local text = require("mayon.ui.text")

	local function setup_colors()
		local palette = require("mayon.generated").palette
		return {
			bg = palette.bg,
			selection = palette.selection,
			purple = palette.purple,
			position_bg = palette.bg,
			fg = palette.fg,
			bright = palette.brightFg,
			gray = palette.muted,
			blue = palette.blue,
			cyan = palette.cyan,
			green = palette.green,
			accent = palette.muted,
			orange = palette.orange,
			red = palette.red,
			diag_warn = palette.yellow,
		}
	end

	local Space = { provider = " " }
	local Align = { provider = "%=" }
	local function redraw_status()
		vim.cmd("redrawstatus")
	end

	-- Statusline providers parse %, and byte counts mismeasure Chinese names.
	local mode_colors = {
		n = "blue",
		i = "green",
		v = "yellow",
		V = "yellow",
		["\22"] = "yellow",
		c = "cyan",
		s = "yellow",
		S = "yellow",
		["\19"] = "yellow",
		R = "red",
		r = "cyan",
		["!"] = "yellow",
		t = "cyan",
	}
	local mode_names = {
		n = "NORMAL",
		niI = "NORMAL",
		niR = "NORMAL",
		niV = "NORMAL",
		no = "O-PENDING",
		nov = "O-PENDING",
		noV = "O-PENDING",
		i = "INSERT",
		ic = "INSERT",
		ix = "INSERT",
		v = "VISUAL",
		V = "V-LINE",
		["\22"] = "V-BLOCK",
		s = "SELECT",
		S = "S-LINE",
		["\19"] = "S-BLOCK",
		R = "REPLACE",
		Rv = "V-REPLACE",
		c = "COMMAND",
		cv = "EX",
		r = "PROMPT",
		rm = "MORE",
		["r?"] = "CONFIRM",
		["!"] = "SHELL",
		t = "TERMINAL",
	}
	local short_modes = {
		n = "N",
		i = "I",
		v = "V",
		V = "V",
		["\22"] = "V",
		c = "C",
		s = "S",
		S = "S",
		R = "R",
		r = "P",
		["!"] = "!",
		t = "T",
	}
	local ViMode = {
		{
			provider = "●",
			hl = function(self)
				return { fg = mode_colors[self.mode:sub(1, 1)] or "blue" }
			end,
		},
		{
			provider = function(self)
				local name = mode_names[self.mode] or self.mode:upper()
				return " " .. (short_modes[self.mode:sub(1, 1)] or name:sub(1, 1)) .. " "
			end,
			hl = function(self)
				return { fg = mode_colors[self.mode:sub(1, 1)] or "blue" }
			end,
		},
	}
	ViMode.init = function(self)
		self.mode = vim.fn.mode(1)
	end
	ViMode.update = {
		"ModeChanged",
		pattern = "*:*",
		callback = vim.schedule_wrap(redraw_status),
	}

	local FileNameBlock = {
		init = function(self)
			self.filename = vim.api.nvim_buf_get_name(0)
		end,
	}
	local FileName = {
		provider = function(self)
			if self.filename == "" then
				return "[No Name]"
			end
			return text.fit(vim.fn.fnamemodify(self.filename, ":~:."), math.max(5, math.floor(vim.o.columns * 0.50)))
		end,
		hl = { fg = "fg" },
	}
	local FileIcon = {
		init = function(self)
			self.filename = vim.api.nvim_buf_get_name(0)
			self.file_icon, self.file_icon_hl = require("mayon.ui.icons").get(self.filename)
		end,
		provider = function(self)
			return self.file_icon
		end,
		hl = function(self)
			return self.file_icon_hl
		end,
	}
	local CompactFileName = {
		init = function(self)
			self.filename = vim.api.nvim_buf_get_name(0)
		end,
		{
			init = function(self)
				self.file_icon, self.file_icon_hl = require("mayon.ui.icons").get(self.filename)
			end,
			provider = function(self)
				return self.file_icon
			end,
			hl = function(self)
				return self.file_icon_hl
			end,
		},
		{
			provider = function(self)
				if self.filename == "" then
					return "[No Name]"
				end
				return text.fit(vim.fn.fnamemodify(self.filename, ":t"), vim.o.columns < 50 and 4 or 6)
			end,
			hl = { fg = "fg" },
		},
	}
	local FileFlags = {
		{
			condition = function()
				return vim.bo.modified
			end,
			provider = " [+]",
			hl = { fg = "orange" },
		},
		{
			condition = function()
				return not vim.bo.modifiable or vim.bo.readonly
			end,
			provider = " RO",
			hl = { fg = "orange" },
		},
	}
	FileNameBlock = utils.insert(FileNameBlock, FileIcon, FileName, { provider = "%<" })

	local Diagnostics = {
		condition = function()
			return #vim.diagnostic.get(0, { severity = { min = vim.diagnostic.severity.WARN } }) > 0
		end,
		{
			condition = function()
				return #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.WARN }) > 0
			end,
			provider = function()
				return "▲" .. #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.WARN }) .. " "
			end,
			hl = { fg = "diag_warn" },
		},
		{
			condition = function()
				return #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.ERROR }) > 0
			end,
			provider = function()
				return "●" .. #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.ERROR }) .. " "
			end,
			hl = { fg = "red" },
		},
		update = { "DiagnosticChanged", "BufEnter" },
	}

	local Recording = {
		condition = function()
			return vim.fn.reg_recording() ~= ""
		end,
		provider = function()
			return "● REC @" .. vim.fn.reg_recording() .. " "
		end,
		hl = { fg = "red", bold = true },
	}
	local SearchCount = {
		condition = function()
			return vim.o.columns >= 80 and vim.v.hlsearch == 1
		end,
		provider = function()
			local ok, count = pcall(vim.fn.searchcount, { maxcount = 999, timeout = 20 })
			if not ok or not count.total or count.total == 0 then
				return ""
			end
			if count.incomplete == 1 then
				return "[…] "
			end
			return "[" .. count.current .. "/" .. count.total .. (count.incomplete == 2 and "+" or "") .. "] "
		end,
		hl = { fg = "fg" },
	}
	vim.api.nvim_create_autocmd({ "RecordingEnter", "RecordingLeave", "LspAttach", "LspDetach" }, {
		group = vim.api.nvim_create_augroup("HeirlineState", { clear = true }),
		callback = vim.schedule_wrap(redraw_status),
	})
	vim.api.nvim_create_autocmd("LspRequest", {
		group = "HeirlineState",
		callback = function(ev)
			local data = ev.data or {}
			local request = data.request or {}
			local client = vim.lsp.get_client_by_id(data.client_id)
			if client and client.name == "copilot" and request.method == "textDocument/inlineCompletion" then
				vim.schedule(redraw_status)
			end
		end,
	})
	local Encoding = {
		condition = function()
			return vim.o.columns >= 120
		end,
		provider = function()
			return " "
				.. (vim.bo.fileencoding ~= "" and vim.bo.fileencoding:upper() or "UTF-8")
				.. " "
				.. (vim.bo.fileformat == "dos" and "CRLF" or "LF")
				.. " "
		end,
		hl = { fg = "gray" },
	}

	local Ruler = {
		{
			provider = function()
				return " %l:%v %p%% "
			end,
			hl = { fg = "gray" },
		},
	}

	vim.api.nvim_create_autocmd("User", {
		group = vim.api.nvim_create_augroup("HeirlineCodeCompanion", { clear = true }),
		pattern = { "CodeCompanionRequestStarted", "CodeCompanionRequestFinished" },
		callback = function(args)
			local data = args.data or {}
			local id = data.id
			if args.match == "CodeCompanionRequestStarted" and id ~= nil and not codecompanion_requests[id] then
				local adapter = data.adapter
				codecompanion_requests[id] = adapter and (adapter.formatted_name or adapter.name) or "CodeCompanion"
			elseif args.match == "CodeCompanionRequestFinished" and id ~= nil then
				codecompanion_requests[id] = nil
			end
			vim.cmd("redrawstatus")
		end,
	})
	local AI = {
		provider = function()
			local state = ai_status()
			local name = ({ copilot = "Copilot", deepseek = "DeepSeek", off = "AI off" })[state.provider]
				or state.provider
			if state.provider == "deepseek" and (not vim.env.DEEPSEEK_API_KEY or vim.env.DEEPSEEK_API_KEY == "") then
				name = "DeepSeek key?"
			end
			local busy = state.completion_generating and " …" or ""
			local cc = state.codecompanion_generating and " · CC …"
				or (state.codecompanion_enabled and " · CC" or "")
			return " " .. name .. busy .. cc .. " "
		end,
		hl = function()
			local state = ai_status()
			if state.completion_generating or state.codecompanion_generating then
				return { fg = "blue" }
			end
			return { fg = state.provider == "copilot" and "green" or state.provider == "off" and "gray" or "cyan" }
		end,
		-- Read the small state snapshot on redraw; request events can arrive
		-- before Heirline update caches are invalidated. Never cache busy text.
	}

	local Debug = {
		provider = function()
			local debug = package.loaded["mayon.features.debug"]
			return debug and debug.state ~= "" and ("  " .. debug.state .. " ") or ""
		end,
		hl = { fg = "gray" },
	}

	local DefaultStatusline = {
		ViMode,
		{ provider = " │ ", hl = { fg = "gray" } },
		{ flexible = 3, FileNameBlock, CompactFileName, {} },
		FileFlags,
		{
			provider = function()
				return "  │ "
			end,
			hl = { fg = "gray" },
		},
		Diagnostics,
		Align,
		Recording,
		Debug,
		SearchCount,
		AI,
		{
			condition = function()
				return vim.o.columns >= 120
			end,
			Encoding,
		},
		Ruler,
	}

	local SpecialStatusline = {
		condition = function()
			return conditions.buffer_matches({
				buftype = { "nofile", "prompt", "help", "quickfix", "terminal" },
				filetype = { "^git.*", "fugitive", "fzf", "qf", "oil" },
			})
		end,
		ViMode,
		Space,
		{
			provider = function()
				local ft = vim.bo.filetype
				if ft:match("^snacks_picker") then
					for _, picker in ipairs(require("snacks").picker.get()) do
						for _, part in ipairs({ "list", "input", "preview" }) do
							local pane = picker[part]
							if pane and pane.win and pane.win.win == vim.api.nvim_get_current_win() then
								if picker.opts.source == "explorer" then
									return " explorer "
								end
								local title = picker.opts.title or picker.opts.source or "Search"
								return " " .. text.fit(title:gsub("_", " "):gsub("^%l", string.upper), 28) .. " "
							end
						end
					end
					return " Files & search "
				end
				if ft == "oil" then
					local path = require("oil").get_current_dir() or "Directory"
					return " "
						.. text.fit(vim.fn.fnamemodify(path, ":~:."), math.max(12, math.floor(vim.o.columns * 0.5)))
						.. " "
				end
				local names = {
					help = "Help",
					qf = "Quickfix",
					terminal = "Terminal",
					grug_far = "Search & replace",
					["dap-view"] = "Debug",
					["dap-repl"] = "Debug REPL",
				}
				local name = names[ft] or names[vim.bo.buftype] or (ft ~= "" and ft:gsub("_", " ") or "Tools")
				return " " .. text.fit(name, 28) .. " "
			end,
			hl = { fg = "fg", bold = true },
		},
		Align,
		Debug,
		Ruler,
	}

	local function IsCodeCompanion()
		return package.loaded.codecompanion and vim.bo.filetype == "codecompanion"
	end
	local function cc_stat(icon, key)
		return {
			condition = function(self)
				return (self.meta[key] or 0) > 0
			end,
			provider = function(self)
				return " " .. icon .. " " .. self.meta[key] .. " "
			end,
			hl = { fg = "gray" },
		}
	end
	vim.api.nvim_create_autocmd("User", {
		group = "HeirlineCodeCompanion",
		pattern = { "CodeCompanionChatOpened", "CodeCompanionChatModel", "CodeCompanionChatDone" },
		callback = vim.schedule_wrap(redraw_status),
	})
	local CodeCompanionStatusline = {
		condition = IsCodeCompanion,
		init = function(self)
			self.meta = (_G.codecompanion_chat_metadata or {})[vim.api.nvim_get_current_buf()] or {}
		end,
		ViMode,
		Space,
		{
			provider = function(self)
				local a = self.meta.adapter
				return "󰚩 " .. text.fit((a and a.name) or "CodeCompanion", 24) .. " "
			end,
			hl = { fg = "accent", bold = true },
		},
		Align,
		cc_stat("Σ", "tokens"),
		cc_stat("⟳", "cycles"),
		cc_stat("⧉", "context_items"),
		cc_stat("⚒", "tools"),
		Ruler,
	}

	local DashboardStatusline = {
		condition = function()
			return vim.bo.filetype == "snacks_dashboard"
		end,
		ViMode,
		{ provider = "  dashboard", hl = { fg = "gray" } },
		Align,
		{ provider = "q Quit ", hl = { fg = "gray" } },
	}

	local StatusLines = {
		hl = function()
			return conditions.is_active() and "StatusLine" or "StatusLineNC"
		end,
		fallthrough = false,
		DashboardStatusline,
		CodeCompanionStatusline,
		SpecialStatusline,
		DefaultStatusline,
	}

	heirline.setup({ statusline = StatusLines })
	heirline.load_colors(setup_colors())

	vim.api.nvim_create_autocmd("ColorScheme", {
		group = vim.api.nvim_create_augroup("Heirline", { clear = true }),
		-- Refresh after all theme adapters so cached Heirline colours see overrides.
		callback = vim.schedule_wrap(function()
			utils.on_colorscheme(setup_colors)
			vim.cmd.redrawstatus()
			vim.cmd.redrawtabline()
		end),
	})
end

return M
