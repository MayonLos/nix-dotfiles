-- A quiet workspace rail: editing mode, location, attention, then cursor position.
local M = {}
local ready = false

function M.setup()
	if ready then
		return
	end
	ready = true
	local heirline = require("heirline")
	local conditions = require("heirline.conditions")
	local utils = require("heirline.utils")

	local function setup_colors()
		return {
			bg = utils.get_highlight("StatusLine").bg,
			fg = utils.get_highlight("StatusLine").fg,
			gray = utils.get_highlight("NonText").fg,
			blue = utils.get_highlight("Function").fg,
			green = utils.get_highlight("String").fg,
			purple = utils.get_highlight("Statement").fg,
			orange = utils.get_highlight("Constant").fg,
			red = utils.get_highlight("DiagnosticError").fg,
			diag_warn = utils.get_highlight("DiagnosticWarn").fg,
			diag_info = utils.get_highlight("DiagnosticInfo").fg,
			diag_hint = utils.get_highlight("DiagnosticHint").fg,
			git_add = utils.get_highlight("Added").fg or utils.get_highlight("diffAdded").fg,
			git_change = utils.get_highlight("Changed").fg or utils.get_highlight("diffChanged").fg,
			git_del = utils.get_highlight("Removed").fg or utils.get_highlight("diffRemoved").fg,
		}
	end

	local Space = { provider = " " }
	local Align = { provider = "%=" }
	local function redraw_status()
		vim.cmd("redrawstatus")
	end

	-- Statusline providers parse %, and byte counts mismeasure Chinese names.
	local function text(value, width)
		value = tostring(value):gsub("[\r\n\t]", " ")
		if width and vim.fn.strwidth(value) > width then
			local result = ""
			for index = 0, vim.fn.strchars(value) - 1 do
				local char = vim.fn.strcharpart(value, index, 1)
				if vim.fn.strwidth(result .. char .. "…") > width then
					break
				end
				result = result .. char
			end
			value = result .. "…"
		end
		return (value:gsub("%%", "%%%%"))
	end

	local function badge(color, inner)
		inner.hl = function(self)
			return { fg = type(color) == "function" and color(self) or color, bg = "bg", bold = true }
		end
		return inner
	end

	local mode_colors = {
		n = "blue",
		i = "green",
		v = "purple",
		V = "purple",
		["\22"] = "purple",
		c = "orange",
		s = "purple",
		S = "purple",
		["\19"] = "purple",
		R = "red",
		r = "red",
		["!"] = "red",
		t = "green",
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
	local ViMode = badge(function(self)
		return mode_colors[self.mode:sub(1, 1)] or "blue"
	end, {
		provider = function(self)
			local name = mode_names[self.mode] or self.mode:upper()
			return " ▎" .. (vim.o.columns < 80 and name:sub(1, 1) or name) .. " "
		end,
	})
	ViMode.init = function(self)
		self.mode = vim.fn.mode(1)
	end
	ViMode.update = {
		"ModeChanged",
		pattern = "*:*",
		callback = vim.schedule_wrap(redraw_status),
	}

	local Git = {
		condition = conditions.is_git_repo,
		init = function(self)
			self.status = vim.b.gitsigns_status_dict
		end,
		hl = { fg = "gray" },
		{
			provider = function(self)
				return " " .. text(self.status.head, math.max(8, math.floor(vim.o.columns * 0.12))) .. " "
			end,
		},
		{
			provider = function(self)
				local c = self.status.added or 0
				return c > 0 and ("+" .. c .. " ") or ""
			end,
			hl = { fg = "git_add" },
		},
		{
			provider = function(self)
				local c = self.status.changed or 0
				return c > 0 and ("~" .. c .. " ") or ""
			end,
			hl = { fg = "git_change" },
		},
		{
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
			local path = vim.fn.fnamemodify(self.filename, ":~:.:h")
			if self.filename == "" then
				return "scratch"
			end
			return text(path == "." and "workspace" or path, math.max(10, math.floor(vim.o.columns * 0.16)))
		end,
		hl = { fg = "fg" },
	}
	local FileFlags = {
		{
			condition = function()
				return vim.bo.modified
			end,
			provider = " ●",
			hl = { fg = "green" },
		},
		{
			condition = function()
				return not vim.bo.modifiable or vim.bo.readonly
			end,
			provider = " 󰌾",
			hl = { fg = "orange" },
		},
	}
	FileNameBlock = utils.insert(
		FileNameBlock,
		{ provider = "󰉋 ", hl = { fg = "gray" } },
		FileName,
		FileFlags,
		{ provider = "%<" }
	)

	local Navic = {
		condition = function()
			local ok, navic = pcall(require, "nvim-navic")
			return vim.o.columns >= 120 and ok and navic.is_available()
		end,
		-- Use raw symbol data: truncating navic's formatted statusline would cut
		-- highlight escapes in half. The scope still gets one quiet text colour.
		provider = function()
			local data = require("nvim-navic").get_data() or {}
			local parts = {}
			for i = math.max(1, #data - 2), #data do
				parts[#parts + 1] = (data[i].icon or "") .. data[i].name
			end
			if #parts == 0 then
				return ""
			end
			return " › " .. text(table.concat(parts, " › "), math.floor(vim.o.columns * 0.18))
		end,
		hl = { fg = "gray" },
	}

	local function diag_icon(severity)
		local signs = vim.diagnostic.config().signs
		return type(signs) == "table" and signs.text and signs.text[severity] or ""
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
			provider = function(self)
				return self.infos > 0 and (diag_icon(vim.diagnostic.severity.INFO) .. self.infos .. " ")
			end,
			hl = { fg = "diag_info" },
		},
		{
			provider = function(self)
				return self.hints > 0 and (diag_icon(vim.diagnostic.severity.HINT) .. self.hints .. " ")
			end,
			hl = { fg = "diag_hint" },
		},
	}
	local LSPActive = {
		condition = conditions.lsp_attached,
		init = function(self)
			local attached = {}
			for _, client in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
				attached[client.id] = true
			end
			local lsp = package.loaded["mayon.lsp"]
			local progress = lsp and lsp.progress_status and lsp.progress_status() or {}
			local count, names = 0, {}
			for _, task in ipairs(progress) do
				if attached[task.id] then
					count = count + (task.task_count or 1)
					names[#names + 1] = task.name or "LSP"
				end
			end
			self.busy = #names > 0
			-- Raw progress messages can contain several rapidly changing file
			-- counters. Keep the status rail stable; the LSP owns those details.
			self.label = self.busy
					and ("⋯ " .. (#names == 1 and names[1] or "LSP") .. (count > 1 and (" · " .. count .. " tasks") or ""))
				or "● LSP"
		end,
		provider = function(self)
			return text(self.label, math.max(8, math.min(26, math.floor(vim.o.columns * 0.20)))) .. "  "
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
			return vim.v.hlsearch == 1
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
		pattern = { "GitSignsUpdate", "MayonLspProgressChanged" },
		callback = vim.schedule_wrap(redraw_status),
	})
	local FilePercent = { provider = "%p%% ", hl = { fg = "gray" } }
	local Ruler = {
		provider = function()
			return vim.o.columns < 80 and " %l:%v " or " LN %l : %v "
		end,
		hl = "MayonPosition",
	}
	local Language = {
		condition = function()
			return vim.o.columns >= 80 and vim.bo.filetype ~= ""
		end,
		provider = function()
			return text(vim.bo.filetype, 14) .. "  "
		end,
		hl = { fg = "gray" },
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
	local CodeCompanion = {
		condition = function()
			return cc.count > 0
		end,
		provider = function()
			return "⋯ " .. text(cc.name, 18) .. (cc.count > 1 and (" ×" .. cc.count) or "") .. " "
		end,
		hl = { fg = "purple", bold = true },
	}

	local DefaultStatusline = {
		ViMode,
		Space,
		-- Drop optional context before Neovim truncates diagnostics on narrow UIs.
		{ flexible = 3, FileNameBlock, {} },
		{ flexible = 4, Navic, {} },
		Space,
		{ flexible = 2, Git, {} },
		Space,
		Align,
		Recording,
		SearchCount,
		CodeCompanion,
		Diagnostics,
		{ flexible = 1, LSPActive, {} },
		Language,
		FilePercent,
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
								return " " .. text(title:gsub("_", " "):gsub("^%l", string.upper), 28) .. " "
							end
						end
					end
					return " Files & search "
				end
				local names = { help = "Help", qf = "Quickfix", terminal = "Terminal", grug_far = "Search & replace" }
				local name = names[ft] or names[vim.bo.buftype] or (ft ~= "" and ft:gsub("_", " ") or "Tools")
				return " " .. text(name, 28) .. " "
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
				return "󰚩 " .. text((a and a.name) or "CodeCompanion", 24) .. " "
			end,
			hl = { fg = "purple", bold = true },
		},
		Align,
		cc_stat("Σ", "tokens"),
		cc_stat("⟳", "cycles"),
		cc_stat("⧉", "context_items"),
		cc_stat("⚒", "tools"),
		Ruler,
	}

	local StatusLines = {
		hl = function()
			return conditions.is_active() and "StatusLine" or "StatusLineNC"
		end,
		fallthrough = false,
		CodeCompanionStatusline,
		SpecialStatusline,
		DefaultStatusline,
	}

	heirline.setup({ statusline = StatusLines, tabline = require("mayon.tabline").build(text) })
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
