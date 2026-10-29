-- A quiet workspace rail: editing mode, location, attention, then cursor position.
local M = {}
local ready = false

function M.setup()
	if ready then
		return
	end
	ready = true
	vim.ui.progress_status() -- Initialize the native collector before LSP progress can arrive.
	require("mayon.config.loader").pack("heirline.nvim")
	local heirline = require("heirline")
	local conditions = require("heirline.conditions")
	local utils = require("heirline.utils")
	local text = require("mayon.ui.text")

	local function setup_colors()
		local palette = require("mayon.generated").palette
		return {
			bg = palette.deep,
			selection = palette.selection,
			purple = palette.purple,
			position_bg = palette.surface,
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
			diag_info = palette.blue,
			diag_hint = palette.cyan,
			git_add = palette.green,
			git_change = palette.yellow,
			git_del = palette.red,
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
		v = "blue",
		V = "blue",
		["\22"] = "blue",
		c = "diag_warn",
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
			provider = " ● ",
			hl = function(self)
				return { fg = mode_colors[self.mode:sub(1, 1)] or "blue" }
			end,
		},
		{
			provider = function(self)
				local name = mode_names[self.mode] or self.mode:upper()
				return (short_modes[self.mode:sub(1, 1)] or name:sub(1, 1)) .. " "
			end,
			hl = { fg = "gray" },
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

	local Git = {
		condition = function()
			return vim.o.columns >= 80 and conditions.is_git_repo()
		end,
		{ provider = "  " },
		{
			provider = function()
				local n = (vim.b.gitsigns_status_dict or {}).added or 0
				return n > 0 and ("+" .. n .. " ") or ""
			end,
			hl = { fg = "git_add" },
		},
		{
			provider = function()
				local n = (vim.b.gitsigns_status_dict or {}).changed or 0
				return n > 0 and ("~" .. n .. " ") or ""
			end,
			hl = { fg = "git_change" },
		},
		{
			provider = function()
				local n = (vim.b.gitsigns_status_dict or {}).removed or 0
				return n > 0 and ("-" .. n .. " ") or ""
			end,
			hl = { fg = "git_del" },
		},
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
	FileNameBlock = utils.insert(FileNameBlock, FileName, { provider = "%<" })

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

	local LSPActive = {
		condition = function()
			if not package.loaded["vim.lsp"] or not conditions.lsp_attached() then
				return false
			end
			return vim.bo.busy > 0 or vim.ui.progress_status() ~= ""
		end,
		init = function(self)
			local client_names = {}
			for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
				if client.name ~= "copilot" and client.name ~= "minuet" then
					client_names[#client_names + 1] = client.name
				end
			end
			-- 0.12.4 already escapes percent for statusline use. Decode before
			-- text.fit clips display cells and performs the single final escape.
			self.progress = vim.ui.progress_status():gsub("%%%%", "%%")
			self.busy = vim.bo.busy > 0 or self.progress ~= ""
			table.sort(client_names)
			local spinner = ({ "◌", "◍", "◎", "◍" })[(vim.g.mayon_lsp_spinner or 1)]
			self.label = self.busy and (spinner .. " " .. (self.progress ~= "" and self.progress or "busy"))
				or (client_names[1] or "")
		end,
		provider = function(self)
			return text.fit(self.label, math.max(5, math.min(26, math.floor(vim.o.columns * 0.20)))) .. " "
		end,
		hl = function(self)
			return { fg = self.busy and "blue" or "gray" }
		end,
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
	vim.api.nvim_create_autocmd("User", {
		group = "HeirlineState",
		pattern = "GitSignsUpdate",
		callback = vim.schedule_wrap(redraw_status),
	})
	local Encoding = {
		condition = function()
			return vim.o.columns >= 140
		end,
		provider = function()
			return (vim.bo.fileformat == "dos" and "CRLF" or "LF")
				.. "  "
				.. (vim.bo.fileencoding ~= "" and vim.bo.fileencoding:upper() or "UTF-8")
				.. "  "
				.. (vim.bo.expandtab and "Spaces " or "Tabs ")
				.. vim.bo.shiftwidth
				.. " "
		end,
		hl = { fg = "gray" },
	}
	local Ruler = {
		{
			provider = function()
				return " %l:%v "
			end,
			hl = { fg = "gray" },
		},
	}

	local cc = { count = 0, name = nil, requests = {}, order = {} }
	vim.api.nvim_create_autocmd("User", {
		group = vim.api.nvim_create_augroup("HeirlineCodeCompanion", { clear = true }),
		pattern = { "CodeCompanionRequestStarted", "CodeCompanionRequestFinished" },
		callback = function(args)
			local data = args.data or {}
			local id = data.id
			if args.match == "CodeCompanionRequestStarted" and id ~= nil and not cc.requests[id] then
				local adapter = data.adapter
				cc.requests[id] = adapter and (adapter.formatted_name or adapter.name) or "CodeCompanion"
				cc.order[#cc.order + 1] = id
			elseif args.match == "CodeCompanionRequestFinished" and id ~= nil then
				cc.requests[id] = nil
				for index, key in ipairs(cc.order) do
					if key == id then
						table.remove(cc.order, index)
						break
					end
				end
			end
			cc.count = #cc.order
			cc.name = cc.requests[cc.order[#cc.order]]
			vim.cmd("redrawstatus")
		end,
	})
	vim.api.nvim_create_autocmd("Progress", {
		group = vim.api.nvim_create_augroup("HeirlineNativeProgress", { clear = true }),
		callback = vim.schedule_wrap(function()
			vim.g.mayon_lsp_spinner = ((vim.g.mayon_lsp_spinner or 1) % 4) + 1
			redraw_status()
		end),
	})
	local CodeCompanion = {
		condition = function()
			return cc.count > 0
		end,
		provider = function()
			if vim.o.columns < 50 then
				return "⋯" .. (cc.count > 1 and ("×" .. cc.count) or "") .. " "
			end
			local width = math.max(5, math.min(18, math.floor(vim.o.columns * 0.18)))
			return "⋯ "
				.. text.fit(cc.name or "CodeCompanion", width)
				.. (cc.count > 1 and (" ×" .. cc.count) or "")
				.. " "
		end,
		hl = { fg = "accent", bold = true },
	}

	local AI = {
		condition = function()
			local completion = package.loaded["mayon.features.ai_completion"]
			return vim.o.columns >= 60 and completion and (completion.busy or completion.pending > 0)
		end,
		provider = function()
			local completion = package.loaded["mayon.features.ai_completion"]
			local provider = completion and completion.provider or "copilot"
			local name = ({ copilot = "Copilot", deepseek = "DeepSeek", off = "AI off" })[provider] or provider
			local busy = completion and (completion.busy or completion.pending > 0) and " …" or ""
			return " " .. name .. busy .. " "
		end,
		hl = { fg = "accent" },
		update = { "ModeChanged", "BufEnter", "CursorHold", "User" },
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
		{ provider = " · ", hl = { fg = "accent" } },
		{ flexible = 3, FileNameBlock, CompactFileName, {} },
		FileFlags,
		Git,
		Align,
		Recording,
		Debug,
		SearchCount,
		Diagnostics,
		{ flexible = 1, LSPActive, {} },
		CodeCompanion,
		{ flexible = 5, AI, {} },
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
