-- Public Snacks renderer hook; notification history and dismissal stay native.
local M = {}

function M.render(buf, notif, ctx)
	local level = notif.level:sub(1, 1):upper() .. notif.level:sub(2)
	local rail = "SnacksNotifierIcon" .. level
	local edge = "FloatBorder"
	ctx.opts.title, ctx.opts.footer = nil, nil
	ctx.opts.border = {
		{ "╭", edge },
		{ "─", edge },
		{ "╮", edge },
		{ "│", edge },
		{ "╯", edge },
		{ "─", edge },
		{ "╰", rail },
		{ "▎", rail },
	}
	local lines = vim.split(notif.msg, "\n", { plain = true })
	if notif.title and notif.title ~= "" then
		table.insert(lines, 1, notif.title)
	end
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	for row = 0, #lines - 1 do
		vim.api.nvim_buf_set_extmark(buf, ctx.ns, row, 0, {
			end_col = #lines[row + 1],
			hl_group = row == 0 and "MayonNotificationTitle" or "MayonNotificationBody",
		})
	end
end

return M
