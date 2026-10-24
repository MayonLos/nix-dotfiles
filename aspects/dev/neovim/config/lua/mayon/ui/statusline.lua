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
			gray = palette.fg,
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
		i = "cyan",
		v = "yellow",
		V = "yellow",
		["\22"] = "yellow",
		c = "blue",
		s = "yellow",
		S = "yellow",
		["\19"] = "yellow",
		R = "yellow",
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
		provider = function(self)
			local name = mode_names[self.mode] or self.mode:upper()
			local label = vim.o.columns < 80 and (short_modes[self.mode:sub(1, 1)] or name:sub(1, 1)) or name
			return " " .. label .. " "
		end,
		hl = function(self)
			local key = mode_colors[self.mode:sub(1, 1)] or "blue"
			return { fg = key, bg = "selection", bold = true }
		end,
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
		init = function(self)
			self.status = vim.b.gitsigns_status_dict or {}
		end,
		hl = { fg = "purple" },
		{
			provider = function(self)
				return text.fit(self.status.head or "git", math.max(6, math.floor(vim.o.columns * 0.12))) .. " "
			end,
		},
		{
			condition = function()
				return vim.o.columns >= 120
			end,
			provider = function(self)
				local c = self.status.added or 0
				return c > 0 and ("+" .. c .. " ") or ""
			end,
			hl = { fg = "git_add" },
		},
		{
			condition = function()
				return vim.o.columns >= 120
			end,
			provider = function(self)
				local c = self.status.changed or 0
				return c > 0 and ("~" .. c .. " ") or ""
			end,
			hl = { fg = "git_change" },
		},
		{
			condition = function()
				return vim.o.columns >= 120
			end,
			provider = function(self)
				local c = self.status.removed or 0
				return c > 0 and ("-" .. c .. " ") or ""
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
			return text.fit(vim.fn.fnamemodify(self.filename, ":t"), math.max(5, math.floor(vim.o.columns * 0.30)))
		end,
		hl = { fg = "fg" },
	}
	local CompactFileName = {
		provider = function()
			local filename = vim.api.nvim_buf_get_name(0)
			if filename == "" then
				return "[No Name]"
			end
			return text.fit(vim.fn.fnamemodify(filename, ":t"), vim.o.columns < 50 and 4 or 6)
		end,
		hl = { fg = "fg" },
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

	local function diag_icon(severity)
		return ({
			[vim.diagnostic.severity.ERROR] = "▲",
			[vim.diagnostic.severity.WARN] = "▲",
			[vim.diagnostic.severity.INFO] = "i",
			[vim.diagnostic.severity.HINT] = "·",
		})[severity]
	end

	local Diagnostics = {
		condition = conditions.has_diagnostics,
		init = function(self)
			local sev = vim.diagnostic.severity
			self.errors = #vim.diagnostic.get(0, { severity = sev.ERROR })
			self.warns = #vim.diagnostic.get(0, { severity = sev.WARN })
			self.infos = #vim.diagnostic.get(0, { severity = sev.INFO })
			self.hints = #vim.diagnostic.get(0, { severity = sev.HINT })
		end,
		update = { "DiagnosticChanged", "BufEnter" },
		{
			provider = function(self)
				return self.errors > 0 and (diag_icon(vim.diagnostic.severity.ERROR) .. self.errors .. " ")
			end,
			hl = { fg = "red" },
		},
		{
			provider = function(self)
				return self.warns > 0 and (diag_icon(vim.diagnostic.severity.WARN) .. self.warns .. " ")
			end,
			hl = { fg = "diag_warn" },
		},
		{
			condition = function()
				return vim.o.columns >= 80
			end,
			provider = function(self)
				return self.infos > 0 and (diag_icon(vim.diagnostic.severity.INFO) .. self.infos .. " ")
			end,
			hl = { fg = "diag_info" },
		},
		{
			condition = function()
				return vim.o.columns >= 80
			end,
			provider = function(self)
				return self.hints > 0 and (diag_icon(vim.diagnostic.severity.HINT) .. self.hints .. " ")
			end,
			hl = { fg = "diag_hint" },
		},
	}
	local LSPActive = {
		condition = function()
			if not package.loaded["vim.lsp"] or not conditions.lsp_attached() then
				return false
			end
			if vim.o.columns >= 120 then
				return true
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
			self.label = self.busy and ("◐ " .. (self.progress ~= "" and self.progress or "busy"))
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
			return "● @" .. vim.fn.reg_recording() .. " "
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
				return "search … "
			end
			return count.current .. "/" .. count.total .. (count.incomplete == 2 and "+ " or " ")
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
			return vim.o.columns >= 80 and vim.bo.fileencoding ~= "" and vim.bo.fileencoding:lower() ~= "utf-8"
		end,
		provider = function()
			return vim.bo.fileencoding:upper() .. " "
		end,
		hl = { fg = "gray" },
	}
	local Ruler = {
		{
			provider = function()
				return vim.o.columns >= 120 and " %l:%v · %p%% " or " %l:%v "
			end,
			hl = "MayonPosition",
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
		callback = vim.schedule_wrap(redraw_status),
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
			return vim.o.columns >= 100
		end,
		provider = function()
			local completion = package.loaded["mayon.features.ai_completion"]
			local provider = completion and completion.provider or "copilot"
			local name = provider == "copilot" and "Copilot" or "DeepSeek"
			local busy = completion and (completion.busy or completion.pending > 0) and " …" or ""
			return " AI · " .. name .. busy .. " "
		end,
		hl = { fg = "accent" },
		update = { "ModeChanged", "BufEnter", "CursorHold", "User" },
	}

	local DefaultStatusline = {
		ViMode,
		Space,
		{ flexible = 2, Git, {} },
		-- Drop optional context before Neovim truncates diagnostics on narrow UIs.
		{ flexible = 3, FileNameBlock, CompactFileName, {} },
		-- Buffer state stays visible when the flexible filename contracts.
		FileFlags,
		Space,
		Align,
		Recording,
		SearchCount,
		Diagnostics,
		{ flexible = 1, LSPActive, {} },
		CodeCompanion,
		{ flexible = 5, AI, {} },
		Encoding,
		Ruler,
	}

	local SpecialStatusline = {
		condition = function()
			return conditions.buffer_matches({
				buftype = { "nofile", "prompt", "help", "quickfix", "terminal" },
				filetype = { "^git.*", "fugitive", "fzf", "qf" },
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
								local title = picker.opts.title or picker.opts.source or "Search"
								return " " .. text.fit(title:gsub("_", " "):gsub("^%l", string.upper), 28) .. " "
							end
						end
					end
					return " Files & search "
				end
				local names = { help = "Help", qf = "Quickfix", terminal = "Terminal", grug_far = "Search & replace" }
				local name = names[ft] or names[vim.bo.buftype] or (ft ~= "" and ft:gsub("_", " ") or "Tools")
				return " " .. text.fit(name, 28) .. " "
			end,
			hl = { fg = "fg", bold = true },
		},
		Align,
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
		{ provider = "q 退出 ", hl = { fg = "gray" } },
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

	heirline.setup({ statusline = StatusLines, tabline = require("mayon.ui.tabline").build() })
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
