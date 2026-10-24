local M = {}
local api = vim.api
local ns = api.nvim_create_namespace("MayonAIPanels")
local setup_done = false

local groups = {
	MayonAIPanel = { fg = "brightFg", bg = "deep" },
	MayonAIPanelMuted = { fg = "muted", bg = "deep" },
	MayonAIConnected = { fg = "green", bg = "deep" },
	MayonAIRemoved = { fg = "red", bg = "deep" },
	MayonAIDisconnected = { fg = "dim", bg = "deep" },
	MayonAIActive = { fg = "brightFg", bg = "deep", underline = true, sp = "blue" },
	MayonAIInactive = { fg = "muted", bg = "deep" },
	MayonAIUser = { fg = "muted", bg = "deep", italic = true },
	MayonAIAssistant = { fg = "muted", bg = "deep", bold = true },
	MayonAIUserRail = { fg = "dim", bg = "deep" },
	MayonAITool = { fg = "cyan", bg = "deep" },
	MayonAICode = { fg = "fg", bg = "bg" },
	MayonAIAdd = { fg = "green", bg = "bg" },
	MayonAIDelete = { fg = "red", bg = "bg" },
}

local function hl()
	local palette = require("mayon.generated").palette
	local edge = require("mayon.ui.theme").blend(palette.border, palette.deep, 0.28)
	for name, spec in pairs(groups) do
		local resolved = vim.deepcopy(spec)
		for key, value in pairs(resolved) do
			if value == "edge" then
				resolved[key] = edge
			elseif value == "dim" then
				resolved[key] = require("mayon.ui.theme").blend(palette.muted, palette.deep, 0.45)
			elseif type(value) == "string" and palette[value] then
				resolved[key] = palette[value]
			end
		end
		api.nvim_set_hl(0, name, resolved)
	end
	api.nvim_set_hl(
		0,
		"MayonAIAdd",
		{ fg = palette.brightFg, bg = require("mayon.ui.theme").blend(palette.green, palette.deep, 0.08) }
	)
	api.nvim_set_hl(
		0,
		"MayonAIDelete",
		{ fg = palette.brightFg, bg = require("mayon.ui.theme").blend(palette.red, palette.deep, 0.08) }
	)
	api.nvim_set_hl(
		0,
		"MayonAIDiffAddText",
		{ fg = palette.brightFg, bg = require("mayon.ui.theme").blend(palette.green, palette.deep, 0.12), bold = true }
	)
	api.nvim_set_hl(
		0,
		"MayonAIDiffDeleteText",
		{ fg = palette.brightFg, bg = require("mayon.ui.theme").blend(palette.red, palette.deep, 0.12), bold = true }
	)
	api.nvim_set_hl(0, "NormalFloat", { fg = palette.brightFg, bg = palette.deep })
	api.nvim_set_hl(0, "FloatBorder", { fg = edge, bg = palette.deep })
	api.nvim_set_hl(0, "FloatTitle", { fg = palette.brightFg, bg = palette.deep })
	api.nvim_set_hl(0, "CodeCompanionChatHeader", { fg = palette.muted, bg = palette.deep, bold = true })
	api.nvim_set_hl(0, "CodeCompanionChatSeparator", { fg = edge, bg = palette.deep })
	api.nvim_set_hl(0, "CodeCompanionChatTool", { fg = palette.cyan, bg = palette.deep })
	api.nvim_set_hl(0, "CodeCompanionChatToolGroup", { fg = palette.cyan, bg = palette.deep })
	api.nvim_set_hl(0, "CodeCompanionChatToolText", { fg = palette.fg, bg = palette.deep })
	api.nvim_set_hl(0, "CodeCompanionVirtualText", { fg = palette.purple, bg = palette.deep, italic = true })
	api.nvim_set_hl(0, "CodeCompanionDiffAdd", {
		fg = palette.green,
		bg = require("mayon.ui.theme").blend(palette.green, palette.deep, 0.12),
	})
	api.nvim_set_hl(0, "CodeCompanionDiffDelete", {
		fg = palette.red,
		bg = require("mayon.ui.theme").blend(palette.red, palette.deep, 0.12),
	})
end

local function statusline_buf(buf)
	if buf and api.nvim_buf_is_valid(buf) then
		return buf
	end
	local win = tonumber(vim.g.statusline_winid) or 0
	if win > 0 and api.nvim_win_is_valid(win) then
		return api.nvim_win_get_buf(win)
	end
	return api.nvim_get_current_buf()
end

local function statusline_text(value)
	return tostring(value or ""):gsub("%%", "%%%%")
end

local function is_chat(buf)
	return api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "codecompanion"
end

local function user_role()
	local ok, config = pcall(require, "codecompanion.config")
	return ok and config.interactions.chat.roles.user or "YOU"
end

local function role_headings(buf)
	local user = user_role()
	local users = { [user] = true, Me = true }
	local assistant = { CodeCompanion = true, DEEPSEEK = true }
	local ok, chat = pcall(function()
		local last = require("codecompanion").last_chat()
		return last and last.bufnr == buf and last or nil
	end)
	if ok and chat and chat.adapter then
		local config_ok, config = pcall(require, "codecompanion.config")
		local role = config_ok and config.interactions.chat.roles.llm
		if type(role) == "function" then
			local resolved, value = pcall(role, chat.adapter)
			if resolved and value then
				assistant[tostring(value)] = true
				users[tostring(value)] = nil
			end
		elseif type(role) == "string" then
			assistant[role] = true
		end
		assistant[tostring(chat.adapter.formatted_name or chat.adapter.name or "DeepSeek"):upper()] = true
		local formatted = tostring(chat.adapter.formatted_name or chat.adapter.name or "DeepSeek")
		assistant[formatted] = true
		assistant["CodeCompanion (" .. formatted .. ")"] = true
	end
	return users, assistant
end

local function set_line_hl(buf, row, group, priority)
	api.nvim_buf_set_extmark(buf, ns, row, 0, {
		end_row = row + 1,
		hl_group = group,
		hl_mode = "combine",
		hl_eol = true,
		priority = priority or 5001,
	})
end

local tool_names = {
	Read = true,
	Edit = true,
	Write = true,
	Run = true,
	Search = true,
	Grep = true,
	Fetch = true,
	Browser = true,
	Tool = true,
	Ask = true,
	Glob = true,
	LSP = true,
}

local function decorate_chat(buf)
	if not is_chat(buf) then
		return
	end
	api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	local lines = api.nvim_buf_get_lines(buf, 0, -1, false)
	local user_roles, assistant_roles = role_headings(buf)
	local in_user = false
	local in_code = false
	for row, line in ipairs(lines) do
		local heading = line:match("^##%s+(.+)$")
		if heading then
			in_user = user_roles[heading] == true
			if in_user then
				local label = user_role() == "Me" and "YOU" or user_role():upper()
				api.nvim_buf_set_extmark(buf, ns, row - 1, 0, {
					end_col = #line,
					conceal = "",
					virt_text = { { label, "MayonAIUser" } },
					virt_text_pos = "overlay",
					hl_group = "MayonAIUser",
					hl_eol = true,
					priority = 5001,
				})
			elseif assistant_roles[heading] or heading:match("^CodeCompanion%s+%(") then
				local label = heading:match("%((.-)%)") or heading
				api.nvim_buf_set_extmark(buf, ns, row - 1, 0, {
					end_col = #line,
					conceal = "",
					virt_text = { { label:upper(), "MayonAIAssistant" } },
					virt_text_pos = "overlay",
					hl_group = "MayonAIAssistant",
					hl_eol = true,
					priority = 5001,
				})
			end
		end

		if line:match("^%s*```%S*") or line:match("^%s*~~~%S*") then
			set_line_hl(buf, row - 1, "MayonAICode")
			in_code = not in_code
		elseif in_code then
			local group = line:match("^%s*%+[^+]") and "MayonAIAdd"
				or line:match("^%s*%-[^-]") and "MayonAIDelete"
				or "MayonAICode"
			set_line_hl(buf, row - 1, group)
		elseif not in_user and tool_names[line:match("^%s*>%s*(%a+)%s") or ""] then
			-- CodeCompanion emits tool calls as single blockquote summary lines.
			set_line_hl(buf, row - 1, "MayonAITool")
		elseif in_user and not heading and line ~= "" then
			api.nvim_buf_set_extmark(buf, ns, row - 1, 0, {
				sign_text = "▏",
				sign_hl_group = "MayonAIUserRail",
				priority = 80,
			})
		end
	end
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		vim.wo[win].signcolumn = "yes:1"
		vim.wo[win].winhighlight = "Normal:NormalFloat,EndOfBuffer:NormalFloat,SignColumn:NormalFloat,WinBar:EdgyWinBar"
		vim.wo[win].fillchars = "eob: "
		vim.wo[win].winbar = "%!v:lua.require'mayon.ui.ai_panels'.winbar()"
	end
end

local function diff_counts(buf)
	local target = vim.b[buf].claudecode_diff_target_win
	if not target or not api.nvim_win_is_valid(target) then
		return 0, 0
	end
	local other = api.nvim_win_get_buf(target)
	if not api.nvim_buf_is_valid(other) then
		return 0, 0
	end
	local old = api.nvim_buf_get_lines(other, 0, -1, false)
	local new = api.nvim_buf_get_lines(buf, 0, -1, false)
	local hunks = vim.diff(table.concat(old, "\n"), table.concat(new, "\n"), { result_type = "indices" }) or {}
	local added, removed = 0, 0
	for _, hunk in ipairs(hunks) do
		removed = removed + (hunk[2] or 0)
		added = added + (hunk[4] or 0)
	end
	return added, removed
end

local function provider(buf)
	local ft = vim.bo[buf].filetype
	local cmd_value = vim.b[buf].snacks_terminal and vim.b[buf].snacks_terminal.cmd or ""
	local cmd = (type(cmd_value) == "table" and table.concat(cmd_value, " ") or tostring(cmd_value)):lower()
	if ft == "claudecode" or cmd:find("claude", 1, true) then
		if vim.b[buf].mayon_ai_fixture then
			return "Claude", "OFFLINE FIXTURE", false
		end
		local connected = false
		local ok, claude = pcall(require, "claudecode")
		if ok then
			connected = claude.is_claude_connected()
		end
		return "Claude", connected and "已连接" or "未连接", connected
	elseif ft == "sidekick_terminal" or ft == "sidekick" or cmd:find("codex", 1, true) then
		local tool = vim.b[buf].sidekick_cli
		local name = type(tool) == "table" and tool.name or tool
		name = name or (cmd:find("codex", 1, true) and "codex") or "AI CLI"
		local status = "已启动"
		local ok, sessions = pcall(function()
			return require("sidekick.status").cli()
		end)
		if ok then
			local attached = false
			for _, session in ipairs(sessions or {}) do
				if session.tool == name or session.tool == tostring(name):lower() then
					attached = true
					break
				end
			end
			status = attached and "已连接" or "已启动"
		end
		return tostring(name):lower() == "codex" and "Codex" or tostring(name), status, status == "已连接"
	elseif ft == "codecompanion" then
		local ok, chat = pcall(function()
			local last = require("codecompanion").last_chat()
			return last and last.bufnr == buf and last or nil
		end)
		local adapter = ok and chat and chat.adapter
		local name = adapter and (adapter.formatted_name or adapter.name) or "DeepSeek"
		local model = ""
		if adapter then
			local adapter_utils_ok, adapter_utils = pcall(require, "codecompanion.adapters.utils")
			if adapter_utils_ok then
				local resolved, value = pcall(adapter_utils.resolve_model, adapter, { async = true })
				if resolved then
					model = value or ""
				end
			end
		end
		return name, model ~= "" and (model .. " · ^S 发送") or "就绪 · ^S 发送", true
	end
	return nil, "", false
end

function M.winbar(buf)
	buf = statusline_buf(buf)
	if not api.nvim_buf_is_valid(buf) then
		return ""
	end
	local name, status, connected = provider(buf)
	if not name then
		return ""
	end
	local dot = connected and "%#MayonAIConnected#●%*" or "%#MayonAIDisconnected#●%*"
	local active = name:lower():find("claude", 1, true) and "Claude"
		or name:lower():find("codex", 1, true) and "Codex"
		or name:lower():find("deepseek", 1, true) and "DeepSeek"
	active = active or statusline_text(name)
	local tabs = {}
	for _, label in ipairs({ "Claude", "Codex", "DeepSeek" }) do
		tabs[#tabs + 1] = (label == active and "%#MayonAIActive# " or "%#MayonAIInactive# ") .. label .. " %*"
	end
	return dot .. " " .. table.concat(tabs, "") .. "%=%#MayonAIPanelMuted#" .. statusline_text(status) .. " %*"
end

function M.diff_winbar(buf)
	buf = statusline_buf(buf)
	local raw = vim.b[buf].claudecode_diff_tab_name or api.nvim_buf_get_name(buf)
	local path = statusline_text(raw:gsub("^.*[/\\]", ""))
	local added, removed = diff_counts(buf)
	return "%#MayonAIPanel# "
		.. path
		.. "  %#MayonAIConnected#+"
		.. added
		.. "%* %#MayonAIRemoved#−"
		.. removed
		.. "%*%="
		.. "%#MayonAIConnected# ,a 接受%*  %#MayonAIRemoved#,r 拒绝%*"
end

function M.style_diff(buf)
	local function style(win, added)
		if not win or not api.nvim_win_is_valid(win) or not vim.wo[win].diff then
			return
		end
		if not vim.w[win].mayon_claude_style then
			vim.w[win].mayon_claude_style =
				{ winhighlight = vim.wo[win].winhighlight, cursorline = vim.wo[win].cursorline }
		end
		vim.wo[win].winhighlight = "Normal:NormalFloat,WinBar:EdgyWinBar,DiffChange:"
			.. (added and "DiffAdd" or "DiffDelete")
			.. ",DiffText:"
			.. (added and "MayonAIDiffAddText" or "MayonAIDiffDeleteText")
		vim.wo[win].cursorline = false
	end
	style(vim.b[buf].claudecode_diff_target_win, false)
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		style(win, true)
		vim.wo[win].winbar = "%!v:lua.require'mayon.ui.ai_panels'.diff_winbar()"
	end
end

local function restore_diff_style(win)
	local saved = vim.w[win].mayon_claude_style
	if saved and not vim.wo[win].diff then
		vim.wo[win].winhighlight = saved.winhighlight
		vim.wo[win].cursorline = saved.cursorline
		vim.w[win].mayon_claude_style = nil
	end
end

local function style_terminal(buf)
	if not api.nvim_buf_is_valid(buf) then
		return
	end
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		vim.wo[win].winhighlight = "Normal:NormalFloat,EndOfBuffer:NormalFloat,WinBar:EdgyWinBar"
		vim.wo[win].fillchars = "eob: "
		local name = provider(buf)
		vim.wo[win].winbar = name and "%!v:lua.require'mayon.ui.ai_panels'.winbar()" or ""
	end
end

function M.setup()
	if setup_done then
		return
	end
	setup_done = true
	hl()
	local group = api.nvim_create_augroup("MayonAIPanels", { clear = true })
	api.nvim_create_autocmd("ColorScheme", {
		group = group,
		callback = hl,
	})
	api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "TextChanged", "TextChangedI" }, {
		group = group,
		callback = function(ev)
			if is_chat(ev.buf) then
				vim.schedule(function()
					decorate_chat(ev.buf)
				end)
			elseif vim.bo[ev.buf].buftype == "terminal" or vim.bo[ev.buf].filetype == "snacks_terminal" then
				style_terminal(ev.buf)
			end
		end,
	})
	api.nvim_create_autocmd("User", {
		group = group,
		pattern = { "CodeCompanionChatOpened", "CodeCompanionChatRestored", "CodeCompanionChatDone" },
		callback = function(ev)
			local buf = ev.data and ev.data.bufnr
			if buf and is_chat(buf) then
				vim.schedule(function()
					if api.nvim_buf_is_valid(buf) then
						decorate_chat(buf)
					end
				end)
			end
		end,
	})
	api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
		group = group,
		callback = function(ev)
			restore_diff_style(api.nvim_get_current_win())
			if vim.b[ev.buf].claudecode_diff_tab_name then
				M.style_diff(ev.buf)
			end
		end,
	})
	api.nvim_create_autocmd("OptionSet", {
		group = group,
		pattern = "diff",
		callback = function()
			local win = api.nvim_get_current_win()
			vim.schedule(function()
				if not api.nvim_win_is_valid(win) then
					return
				end
				restore_diff_style(win)
				local buf = api.nvim_win_get_buf(win)
				if vim.b[buf].claudecode_diff_tab_name then
					M.style_diff(buf)
				end
			end)
		end,
	})
end

-- Open a real CodeCompanion chat buffer and add local-only messages. No request
-- is submitted; this is the fixture used for visual checks.
function M.open_fixture(kind)
	if kind == "chat" then
		local chat = require("codecompanion").chat({ params = { adapter = "deepseek" } })
		assert(chat and chat.bufnr and api.nvim_buf_is_valid(chat.bufnr), "CodeCompanion chat buffer was not created")
		chat:add_buf_message({ role = "user", content = "把通知宽度改成 320，并保持右上角。" })
		chat:add_buf_message({
			role = "llm",
			content = "好的，修改如下：\n\n> Read noctalia.nix · 226 行\n\n```diff\n- width = 380;\n+ width = 320;\n```",
		})
		chat:add_buf_message({ role = "user", content = "" })
		chat.ui:open()
		decorate_chat(chat.bufnr)
		return chat.bufnr
	elseif kind == "terminal" then
		local buf = api.nvim_create_buf(false, true)
		local chan = api.nvim_open_term(buf, {})
		vim.bo[buf].filetype = "snacks_terminal"
		vim.b[buf].snacks_terminal = { cmd = { "claude" } }
		vim.b[buf].mayon_ai_fixture = true
		api.nvim_chan_send(chan, "AI terminal container fixture · offline · CLI output is not simulated\r\n")
		vim.cmd("botright 42vsplit")
		api.nvim_win_set_buf(0, buf)
		style_terminal(buf)
		return buf
	end
	error("fixture kind must be 'chat' or 'terminal'")
end

return M
