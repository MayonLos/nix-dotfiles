-- Exercise the workbench's document identity, real Aerial symbols and AI
-- request state through their public runtime APIs.
vim.o.columns, vim.o.lines = 180, 52
local root = vim.fn.tempname() .. "/工作台"
vim.fn.mkdir(root, "p")
vim.fn.writefile({ "fixture = true" }, root .. "/flake.nix")
local lua_file = root .. "/中文%模块.lua"
local lua_lines = {
	"local M = {}",
	"function M.render_title()",
	"  return '文档工作台'",
	"end",
	"return M",
}
vim.fn.writefile(lua_lines, lua_file)
local tsx_file = root .. "/界面.tsx"
vim.fn.writefile({
	"type Props = { title: string }",
	"export function Header(props: Props) {",
	"  return <h1>{props.title}</h1>",
	"}",
}, tsx_file)

vim.cmd.edit(vim.fn.fnameescape(lua_file))
local doc = vim.api.nvim_get_current_buf()
local header = require("mayon.ui.tabline")
header.refresh()
local rendered = vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true, maxwidth = vim.o.columns })
assert(rendered.str:find("中文%模块.lua", 1, true), "header must render CJK names and a literal percent")
assert(rendered.str:find("工作台", 1, true), "header must identify the project's workspace root")

local doc_window = vim.api.nvim_get_current_win()
vim.cmd.vnew()
local tool_window, tool_buffer = vim.api.nvim_get_current_win(), vim.api.nvim_get_current_buf()
vim.bo[tool_buffer].buftype = "nofile"
vim.bo[tool_buffer].filetype = "snacks_picker_list"
header.refresh()
local focused_tool_header = vim.api.nvim_eval_statusline(vim.o.tabline, {
	use_tabline = true,
	maxwidth = vim.o.columns,
})
assert(
	focused_tool_header.str:find("中文%模块.lua", 1, true),
	"focusing a picker must keep the active document in the header"
)
header.select(doc)
assert(vim.api.nvim_get_current_win() == doc_window, "document selection must focus the document window")
assert(vim.api.nvim_win_get_buf(tool_window) == tool_buffer, "document selection must preserve the tool window")
vim.api.nvim_win_close(tool_window, true)

-- Load the locked Aerial plugin and exercise its real Treesitter symbol data.
vim.api.nvim_exec_autocmds("User", { pattern = "MayonVeryLazy" })
require("lz.n").trigger_load({ "nvim-treesitter", "aerial.nvim" })
vim.wait(100)
local outline = require("mayon.ui.outline")
local aerial = require("aerial")
local outline_mapping = vim.fn.maparg("<leader>o", "n", false, true)
assert(type(outline_mapping.callback) == "function", "Space o should toggle the symbol outline")
assert(outline_mapping.desc == "Toggle Symbol Outline", "Space o should advertise outline behavior")
assert(vim.fn.exists(":BreadcrumbsToggle") == 0, "the removed breadcrumb winbar should not remain discoverable")
assert(vim.fn.maparg("<leader>ub", "n") == "", "the old breadcrumb toggle should be released")
local function wait_for_symbols(buf)
	return vim.wait(5000, function()
		return aerial.num_symbols(buf) > 0
	end, 25)
end
assert(wait_for_symbols(doc), "Aerial should produce symbols for the Lua fixture")
outline.reconcile()
assert(
	vim.wait(1500, function()
		return outline.is_open()
	end),
	"wide source buffer should open its Aerial outline"
)
local outline_win
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
	if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "aerial" then
		outline_win = win
	end
end
assert(outline_win, "Aerial outline window should exist")
local outline_lines =
	table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(outline_win), 0, -1, false), "\n")
assert(
	vim.wait(1500, function()
		return table
			.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(outline_win), 0, -1, false), "\n")
			:find("render_title", 1, true) ~= nil
	end),
	"outline should list a real Lua symbol"
)

vim.api.nvim_buf_set_lines(doc, 0, -1, false, { "-- no Lua symbols remain" })
vim.api.nvim_exec_autocmds("TextChanged", { buffer = doc })
assert(
	vim.wait(5000, function()
		return aerial.num_symbols(doc) == 0 and not outline.is_open()
	end, 25),
	"Aerial should close automatically after the final Lua symbol is removed"
)
vim.api.nvim_buf_set_lines(doc, 0, -1, false, lua_lines)
vim.api.nvim_exec_autocmds("TextChanged", { buffer = doc })
assert(
	vim.wait(5000, function()
		return aerial.num_symbols(doc) > 0 and outline.is_open()
	end, 25),
	"Aerial should restore after source symbols return"
)

-- The shared right outline follows the active source split, not its first owner.
local split_file = root .. "/split.lua"
vim.fn.writefile({ "function split_only_symbol() return 1 end" }, split_file)
vim.cmd.vsplit(vim.fn.fnameescape(split_file))
local split_win = vim.api.nvim_get_current_win()
assert(
	vim.wait(3000, function()
		for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			local b = vim.api.nvim_win_get_buf(w)
			if vim.bo[b].filetype == "aerial" then
				return table
					.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n")
					:find("split_only_symbol", 1, true) ~= nil
			end
		end
		return false
	end),
	"outline should retarget to the newly active code split"
)
vim.api.nvim_set_current_win(doc_window)
assert(
	vim.wait(3000, function()
		for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			local b = vim.api.nvim_win_get_buf(w)
			if vim.bo[b].filetype == "aerial" then
				return table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n"):find("render_title", 1, true)
					~= nil
			end
		end
		return false
	end),
	"outline should retarget when focus returns to the original code split"
)
vim.api.nvim_win_close(split_win, true)

vim.o.columns = 100
outline.reconcile(doc)
assert(not outline.is_open(), "narrow workbench should automatically close the outline")
assert(outline.state().manual_closed == false, "automatic narrow close must not count as a manual close")
vim.o.columns = 180
outline.reconcile(doc)
assert(
	vim.wait(1000, function()
		return outline.is_open()
	end),
	"wide resize should restore the automatic outline"
)
outline.toggle()
assert(not outline.is_open() and outline.state().manual_closed, "manual close should persist for this tab")
outline.reconcile(doc)
assert(not outline.is_open(), "automatic reconciliation must respect a manual close")

-- A manual close is tab-local; a new supported document tab gets its outline.
vim.cmd.tabnew()
local second_tab = vim.api.nvim_get_current_tabpage()
vim.cmd.edit(vim.fn.fnameescape(tsx_file))
local tsx_buf = vim.api.nvim_get_current_buf()
assert(outline.is_supported(tsx_buf), "Aerial should recognize the TSX Treesitter backend")
assert(wait_for_symbols(tsx_buf), "Aerial should produce symbols for the TSX fixture")
outline.reconcile(tsx_buf)
assert(
	vim.wait(1500, function()
		return outline.is_open(second_tab)
	end),
	"new tab should open its outline independently"
)
local tsx_outline_win
for _, win in ipairs(vim.api.nvim_tabpage_list_wins(second_tab)) do
	if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "aerial" then
		tsx_outline_win = win
	end
end
assert(tsx_outline_win, "TSX outline window should exist")
local tsx_lines =
	table.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(tsx_outline_win), 0, -1, false), "\n")
assert(
	vim.wait(1500, function()
		return table
			.concat(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(tsx_outline_win), 0, -1, false), "\n")
			:find("Header", 1, true) ~= nil
	end),
	"outline should list a real TSX symbol"
)
local terminal_buf = vim.api.nvim_create_buf(false, true)
vim.bo[terminal_buf].filetype = "terminal"
vim.api.nvim_set_current_buf(terminal_buf)
outline.reconcile()
assert(not outline.is_open(second_tab), "terminal focus should close and suppress the outline")
local dashboard_buf = vim.api.nvim_create_buf(false, true)
vim.bo[dashboard_buf].filetype = "snacks_dashboard"
vim.api.nvim_set_current_buf(dashboard_buf)
outline.reconcile()
assert(not outline.is_open(second_tab), "dashboard focus should suppress the outline")
vim.api.nvim_set_current_buf(tsx_buf)
outline.reconcile(tsx_buf)
assert(
	vim.wait(1000, function()
		return outline.is_open(second_tab)
	end),
	"returning to the TSX document should restore its automatic outline"
)
vim.cmd.tabprevious()
assert(outline.state().manual_closed, "the first tab's manual close should be remembered independently")
assert(not outline.is_open(), "returning to a manually closed tab should keep its outline hidden")

-- Plain text and tool buffers do not acquire an outline even on a wide view.
local text_file = root .. "/notes.txt"
vim.fn.writefile({ "普通文本没有符号大纲" }, text_file)
vim.cmd.edit(vim.fn.fnameescape(text_file))
local text_buf = vim.api.nvim_get_current_buf()
assert(not outline.is_supported(text_buf), "plain text should not claim an Aerial backend")
outline.reconcile(text_buf)
assert(not outline.is_open(), "unsupported plain text should not display an outline")

-- The status helper tracks overlapping CodeCompanion requests by request ID.
local status = require("mayon.ui.statusline")
status.setup()
local function event(pattern, id)
	vim.api.nvim_exec_autocmds("User", {
		pattern = pattern,
		data = { id = id, adapter = { name = "fixture" } },
	})
end
event("CodeCompanionRequestStarted", "workbench-a")
event("CodeCompanionRequestStarted", "workbench-b")
local ai = status.ai_status()
assert(
	ai.codecompanion_generating and ai.codecompanion_requests == 2,
	"overlapping AI requests should both be reported"
)
local function status_text()
	vim.cmd("redrawstatus")
	return vim.api.nvim_eval_statusline(vim.o.statusline, { maxwidth = vim.o.columns }).str
end
assert(status_text():find("CC …", 1, true), "the rendered statusline should show active CodeCompanion generation")
event("CodeCompanionRequestFinished", "workbench-b")
ai = status.ai_status()
assert(ai.codecompanion_generating and ai.codecompanion_requests == 1, "finishing one request must preserve the other")
assert(status_text():find("CC …", 1, true), "one outstanding request should keep the busy status visible")
event("CodeCompanionRequestFinished", "workbench-a")
ai = status.ai_status()
assert(
	not ai.codecompanion_generating and ai.codecompanion_requests == 0,
	"all finished requests should clear AI activity"
)
assert(not status_text():find("CC …", 1, true), "the rendered statusline should clear after generation ends")

-- A pending inline-completion LSP request must invalidate the statusline UI
-- and reflect the real client's request table without starting Copilot.
local original_get_clients, original_get_client_by_id = vim.lsp.get_clients, vim.lsp.get_client_by_id
local copilot_client = {
	id = 9001,
	name = "copilot",
	requests = { [901] = { type = "pending", method = "textDocument/inlineCompletion" } },
}
vim.lsp.get_clients = function(opts)
	if opts and opts.name == "copilot" then
		return { copilot_client }
	end
	return original_get_clients(opts)
end
vim.lsp.get_client_by_id = function(id)
	if id == copilot_client.id then
		return copilot_client
	end
	return original_get_client_by_id(id)
end
local original_cmd, status_redraws = vim.cmd, 0
vim.cmd = setmetatable({}, {
	__index = original_cmd,
	__call = function(_, command, ...)
		if command == "redrawstatus" then
			status_redraws = status_redraws + 1
		end
		return original_cmd(command, ...)
	end,
})
local function copilot_lsp_request()
	vim.api.nvim_exec_autocmds("LspRequest", {
		data = {
			client_id = copilot_client.id,
			request = { method = "textDocument/inlineCompletion" },
		},
	})
end
copilot_lsp_request()
assert(
	vim.wait(500, function()
		return status_redraws > 0
	end),
	"Copilot LspRequest should schedule a statusline redraw"
)
assert(status.ai_status().completion_generating, "pending Copilot inline completion should be reported as busy")
assert(status_text():find("Copilot …", 1, true), "the rendered statusline should show Copilot generation")
copilot_client.requests = {}
local prior_redraws = status_redraws
copilot_lsp_request()
assert(
	vim.wait(500, function()
		return status_redraws > prior_redraws
	end),
	"Copilot completion finish should schedule a statusline redraw"
)
assert(not status.ai_status().completion_generating, "completed Copilot request should clear busy state")
assert(not status_text():find("Copilot …", 1, true), "the rendered statusline should clear Copilot generation")
vim.cmd = original_cmd
vim.lsp.get_clients, vim.lsp.get_client_by_id = original_get_clients, original_get_client_by_id

print("Document header identity, responsive Aerial outline and overlapping AI status passed")
