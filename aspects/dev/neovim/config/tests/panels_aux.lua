if not package.loaded["which-key"] then
	vim.api.nvim_exec_autocmds("User", { pattern = "MayonVeryLazy" })
	require("lz.n").trigger_load("which-key.nvim")
	vim.wait(50)
end

local whichkey = require("mayon.ui.whichkey").config()
assert(whichkey.win.border == "rounded", "which-key should share the rounded float border")
assert(whichkey.win.row == -1 and whichkey.win.height.max == 10, "which-key should be anchored to the bottom")
assert(
	whichkey.win.width == 0.96
		and whichkey.layout.width.min == math.max(16, math.floor((math.floor(vim.o.columns * 0.96) - 10) / 4)),
	"which-key should form four readable columns"
)
assert(not whichkey.icons.mappings and whichkey.icons.separator == " ", "which-key mappings should use text labels")
assert(not require("mayon.generated").palette.edge, "panel colors must derive edge from the palette border")
local group_hls = {
	WhichKey = require("mayon.generated").palette.blue,
	WhichKeyGroup = require("mayon.generated").palette.muted,
}
assert(group_hls.WhichKey ~= group_hls.WhichKeyGroup, "which-key keys and group labels need distinct colors")

local wk = require("which-key")
assert(wk.did_setup, "which-key setup must finish before exercising its public show API")
vim.keymap.set("n", "<leader>z", function() end, { desc = "show API fixture" })
-- The public command runs which-key.show(). Stub only its blocking getchar
-- step so the real popup render can be inspected without simulating input.
local wk_view = require("which-key.view")
local original_show = wk_view.show
wk_view.show = function(...)
	local result = original_show(...)
	local view = wk_view.view
	if view and view.win and vim.api.nvim_win_is_valid(view.win) then
		vim.g.MayonWhichKeyTitleVisible = vim.inspect(vim.api.nvim_win_get_config(view.win).title)
			:find("␣ LEADER", 1, true) ~= nil
		local wk_win = view.win
		local wk_buf = vim.api.nvim_win_get_buf(wk_win)
		assert(
			vim.api.nvim_buf_line_count(wk_buf) <= vim.api.nvim_win_get_height(wk_win),
			"root which-key groups must fit without clipping"
		)
		local columns = {}
		for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(wk_buf, -1, 0, -1, { details = true })) do
			if mark[4].hl_group == "WhichKey" then
				columns[mark[2]] = columns[mark[2]] or {}
				table.insert(columns[mark[2]], mark[3])
			end
		end
		for row, spans in pairs(columns) do
			if #spans == 4 then
				table.sort(spans)
				local line = vim.api.nvim_buf_get_lines(wk_buf, row, row + 1, false)[1]
				local first = vim.fn.strdisplaywidth(line:sub(1, spans[1]))
				local second = vim.fn.strdisplaywidth(line:sub(1, spans[2]))
				assert(
					second - first >= math.floor(vim.api.nvim_win_get_width(wk_win) / 4) - 3,
					"which-key columns should occupy equal quarters"
				)
			end
		end

		vim.g.MayonWhichKeyColumnsAligned = true
	end
	return result
end
local state = require("which-key.state")
local original_step = state.step
state.step = function()
	wk_view.show()
	return nil, false
end
vim.cmd("WhichKey n <leader>")
assert(require("which-key.config").loaded, "which-key public command should finish deferred setup")
-- Invoke the public show API after setup as well; the step stub only avoids
-- waiting for a real key after rendering the popup.
wk.show({ keys = "<leader>", mode = "n", delay = 0 })
state.step = original_step
wk_view.show = original_show
assert(vim.g.MayonWhichKeyColumnsAligned, "which-key columns did not render")
assert(vim.g.MayonWhichKeyTitleVisible, "public which-key.show() did not render the centered LEADER title")

local panel = require("mayon.features.diagnostic_panel")
local trouble = panel.troubleOptions()
assert(trouble.win.position == "bottom" and trouble.win.size == 12, "Trouble should use the bottom panel")
assert(trouble.indent_guides == false, "Trouble should not draw tree connector guides")
assert(trouble.modes.diagnostics.groups[1][1] == "directory", "diagnostics should group by file path")
assert(trouble.modes.qflist.groups[1][1] == "filename", "Trouble quickfix should group by file")
assert(trouble.win.wo.statuscolumn:find("MayonPanelRail", 1, true), "Trouble panel should have a selection rail")

local scratch = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(scratch, "/tmp/mayon-panel-a.lua")
vim.fn.setqflist({}, "r", {
	items = {
		{
			bufnr = scratch,
			lnum = 12,
			col = 4,
			text = "诊断文字需要截断并保留位置",
			type = "E",
			user_data = "bad-data",
		},
		{ bufnr = scratch, lnum = 13, col = 2, text = "second diagnostic", type = "W" },
	},
	title = "100% checks",
})
local list = vim.fn.getqflist({ all = true })
local rows = panel.formatQuickfix({
	quickfix = 1,
	id = list.id,
	start_idx = 1,
	end_idx = 2,
	winid = 0,
})
assert(#rows == 2 and rows[1]:find("诊断", 1, true), "quickfix formatting lost list entries")
assert(rows[1]:find("12:4", 1, true), "quickfix positions should remain visible")
assert(vim.fn.strwidth(rows[1]) <= 80, "quickfix truncation must honor display-cell width for CJK text")
assert(rows[1]:find("· 2", 1, true), "quickfix file runs should show their grouped count")
assert(rows[2]:find("second diagnostic", 1, true), "quickfix formatting reordered or skipped list entries")
assert(vim.fn.getqflist({ all = true }).items[2].lnum == 13, "quickfix formatter must not mutate jump order")
vim.cmd("copen")
local quickfix_win = vim.api.nvim_get_current_win()
local quickfix_title = panel.quickfixTitle(quickfix_win)
assert(
	quickfix_title:find("●1", 1, true) and quickfix_title:find("▲1", 1, true),
	"quickfix title must count error/warning entries"
)
assert(quickfix_title:find("2 项", 1, true), "quickfix title must include the total")
assert(quickfix_title:find("100%% checks", 1, true), "quickfix titles must escape statusline percent markers")
assert(
	vim.wo[quickfix_win].number and vim.wo[quickfix_win].numberwidth == 1,
	"quickfix panel must enable its one-cell number column"
)
vim.api.nvim_win_set_cursor(quickfix_win, { 1, 0 })
local owner_win
for _, win in ipairs(vim.api.nvim_list_wins()) do
	if win ~= quickfix_win and vim.bo[vim.api.nvim_win_get_buf(win)].filetype ~= "qf" then
		owner_win = win
		break
	end
end
assert(owner_win, "quickfix fixture needs an ordinary editor window")
vim.api.nvim_set_current_win(owner_win)
assert(
	panel.rail(quickfix_win, 1):find("▎", 1, true),
	"status rail must inspect the target quickfix window while unfocused"
)
assert(panel.rail(quickfix_win, 2) == " ", "non-current status rail should leave a blank gutter")

vim.fn.setloclist(owner_win, {}, "r", {
	items = {
		{ bufnr = scratch, lnum = 20, col = 1, text = "local error", type = "E" },
		{ bufnr = scratch, lnum = 21, col = 2, text = "local warning", type = "W" },
	},
	title = "panel fixture",
})
vim.cmd("lopen")
local loclist_win = vim.api.nvim_get_current_win()
local loclist_title = panel.quickfixTitle(loclist_win)
assert(loclist_title:find("位置列表", 1, true), "quickfix title must identify a location list")
assert(
	loclist_title:find("●1", 1, true) and loclist_title:find("▲1", 1, true),
	"location-list title must count its own severities"
)
assert(loclist_title:find("2 项", 1, true), "location-list title must include the total")
assert(loclist_title:find("panel fixture", 1, true), "location-list title must use the active list title")
assert(
	panel
		.formatQuickfix({
			quickfix = 0,
			winid = owner_win,
			id = vim.fn.getloclist(owner_win, { id = 0 }).id,
			start_idx = 1,
			end_idx = 2,
		})[1]
		:find("local error", 1, true),
	"location-list formatter must read the owner window list"
)
vim.cmd("lclose")
vim.api.nvim_set_current_win(owner_win)
vim.cmd("cclose")
vim.fn.setqflist({}, "r")
vim.api.nvim_buf_delete(scratch, { force = true })

local auth_notice = { msg = "Copilot: You are not signed into GitHub.", title = "Sidekick", level = "error" }
assert(require("mayon.ui.notifications").filter(auth_notice))
assert(auth_notice.level == "info" and auth_notice.msg:find("尚未登录", 1, true))
local actual_error = { msg = "Language server crashed", title = "LSP", level = "error" }
assert(require("mayon.ui.notifications").filter(actual_error) and actual_error.level == "error")
