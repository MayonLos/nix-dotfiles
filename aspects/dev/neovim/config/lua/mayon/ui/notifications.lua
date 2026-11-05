-- Public Snacks renderer hook; notification history and dismissal stay native.
local M = {}
local cap_scheduled = false
local tracked = {}

-- Snacks has no "max visible cards" option. Its public history/hide API is the
-- only supported way to trim the stack; this module keeps the <=3 rule here
-- instead of patching notifier internals. `layout.top` is the public layout
-- value Snacks itself uses, reset so retained cards repack after a hide.
function M.cap_visible()
	local snacks = rawget(_G, "Snacks")
	local notifier = snacks and snacks.notifier
	if not notifier or type(notifier.get_history) ~= "function" or type(notifier.hide) ~= "function" then
		return
	end
	local ok, entries = pcall(notifier.get_history, {
		filter = function(notif)
			return not notif.hidden
		end,
		sort = { "added" },
		reverse = true,
	})
	if not ok or type(entries) ~= "table" then
		return
	end
	local seen = {}
	for _, entry in ipairs(entries) do
		seen[entry.id] = true
	end
	for id, entry in pairs(tracked) do
		if entry.hidden then
			tracked[id] = nil
		elseif not seen[id] then
			entries[#entries + 1] = entry
		end
	end
	-- Notifications with history=false still pass the configured filter.
	-- Keep their live references until Snacks marks them hidden.
	local ranks = {}
	for index, entry in ipairs(entries) do
		ranks[entry] = index
	end
	table.sort(entries, function(a, b)
		if a.added and b.added and a.added ~= b.added then
			return a.added > b.added
		end
		return ranks[a] < ranks[b]
	end)
	for index = 4, #entries do
		pcall(notifier.hide, entries[index].id)
		tracked[entries[index].id] = nil
	end
	if #entries > 3 then
		-- Snacks keeps previous card positions; release those positions after
		-- trimming so retained cards pack back into the upper-right corner.
		for index = 1, 3 do
			if entries[index].layout then
				entries[index].layout.top = nil
			end
		end
	end
end

local function schedule_cap()
	if cap_scheduled then
		return
	end
	cap_scheduled = true
	vim.schedule(function()
		cap_scheduled = false
		M.cap_visible()
	end)
end

function M.filter(notif)
	if notif.id then
		tracked[notif.id] = notif
	end
	if notif.msg and notif.msg:find("Copilot", 1, true) and notif.msg:find("not signed", 1, true) then
		notif.msg = "Copilot 尚未登录。运行 :LspCopilotSignIn 完成登录。"
		notif.title = "AI 补全"
		notif.level = "info"
	end
	if notif.msg and (#vim.split(notif.msg, "\n", { plain = true }) > 3 or vim.fn.strdisplaywidth(notif.msg) > 160) then
		-- Long details go to :messages untouched; show a short corner notice.
		vim.api.nvim_echo({ { notif.msg, "Normal" } }, true, {})
		notif.msg = "Details saved to :messages"
	end
	schedule_cap()
	return true
end

function M.render(buf, notif, ctx)
	schedule_cap()
	local level = notif.level:sub(1, 1):upper() .. notif.level:sub(2)
	local rail = "SnacksNotifierIcon" .. level
	-- Severity belongs in a small title mark, never in an asymmetric frame.
	local util = require("mayon.util")
	ctx.opts.wo = ctx.opts.wo or {}
	local links = util.winhl_parse(ctx.opts.wo.winhighlight)
	for from, to in pairs({
		Normal = "NormalFloat",
		NormalNC = "NormalFloat",
		FloatBorder = "FloatBorder",
		FloatTitle = "FloatTitle",
		FloatFooter = "FloatTitle",
		SignColumn = "NormalFloat",
		LineNr = "NormalFloat",
		EndOfBuffer = "NormalFloat",
	}) do
		links[from] = to
	end
	ctx.opts.wo.winhighlight = util.winhl_string(links)
	ctx.opts.border = util.border
	ctx.opts.footer = nil
	ctx.opts.title = {
		{ " ● ", rail },
		{ (notif.title and notif.title ~= "" and notif.title or "Notification") .. " ", "FloatTitle" },
	}
	ctx.opts.title_pos = "center"
	local lines = vim.split(notif.msg, "\n", { plain = true })
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	for row = 0, #lines - 1 do
		vim.api.nvim_buf_set_extmark(buf, ctx.ns, row, 0, {
			end_col = #lines[row + 1],
			hl_group = "MayonNotificationBody",
		})
	end
end

return M
