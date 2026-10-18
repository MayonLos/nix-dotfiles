local root = vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)))
vim.opt.rtp:prepend(root)

package.preload["nvim-web-devicons"] = function()
	return {
		get_icon_color = function()
			return "◆", "#abcdef"
		end,
	}
end
package.preload["mayon.breadcrumbs"] = function()
	return {
		get = function()
			return {
				{ name = "模块", kind = "Class", icon = "◇" },
				{ name = "函数", kind = "Function", icon = "ƒ" },
			}
		end,
	}
end

local statusline = require("mayon.statusline")
statusline.setup()
local function rendered(win)
	local value = statusline.render(win)
	return vim.api.nvim_eval_statusline(value, { winid = win, highlights = true }).str
end
local function has(value, needle, message)
	assert(value:find(needle, 1, true), message or ("expected statusline to contain " .. needle .. ": " .. value))
end

vim.cmd("enew")
vim.o.columns = 160
vim.api.nvim_win_set_width(0, 140)
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_name(buf, "/tmp/中文%名字.lua")
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two" })
vim.bo[buf].modified = true
local win = vim.api.nvim_get_current_win()
local get_width = vim.api.nvim_win_get_width
vim.api.nvim_win_get_width = function(target)
	if target == win then
		return 140
	end
	return get_width(target)
end
local out = rendered(win)
local raw_wide = statusline.render(win)
vim.api.nvim_win_get_width = get_width
has(out, "中文%名字.lua", "Chinese filename and literal percent survive statusline parsing")
has(out, "●", "modified flag is present")
has(out, "◆", "devicon is present")
has(out, "模块", "breadcrumbs are rendered")
has(raw_wide, "%%", "literal percent is escaped in raw statusline text")

vim.diagnostic.set(vim.api.nvim_create_namespace("statusline-test"), buf, {
	{ lnum = 0, col = 0, message = "err", severity = vim.diagnostic.severity.ERROR },
})
out = rendered(vim.api.nvim_get_current_win())
has(out, "1", "diagnostic count is rendered")

vim.api.nvim_exec_autocmds(
	"User",
	{ pattern = "CodeCompanionRequestStarted", data = { id = "a", adapter = { formatted_name = "Adapter A" } } }
)
vim.api.nvim_exec_autocmds(
	"User",
	{ pattern = "CodeCompanionRequestStarted", data = { id = "b", adapter = { name = "Adapter B" } } }
)
vim.api.nvim_exec_autocmds(
	"User",
	{ pattern = "CodeCompanionRequestStarted", data = { id = "a", adapter = { name = "Duplicate" } } }
)
statusline.setup()
out = rendered(vim.api.nvim_get_current_win())
has(out, "Adapter B", "CodeCompanion request adapter is shown")
has(out, "×2", "parallel requests are counted once per id")
vim.api.nvim_exec_autocmds("User", { pattern = "CodeCompanionRequestFinished", data = { id = "a" } })
out = rendered(vim.api.nvim_get_current_win())
has(out, "Adapter B", "finishing one request leaves the other active")
vim.api.nvim_exec_autocmds("User", { pattern = "CodeCompanionRequestFinished", data = { id = "b" } })
vim.api.nvim_exec_autocmds("User", { pattern = "CodeCompanionRequestStarted", data = { adapter = { name = "no id" } } })
out = rendered(vim.api.nvim_get_current_win())
assert(not out:find("⋯", 1, true), "requests without ids are ignored instead of remaining busy forever")
vim.api.nvim_exec_autocmds("User", { pattern = "CodeCompanionRequestFinished", data = {} })

local chat_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_option(chat_buf, "filetype", "codecompanion")
vim.api.nvim_win_set_buf(0, chat_buf)
_G.codecompanion_chat_metadata = {
	[chat_buf] = { adapter = { name = "Chat Adapter" }, tokens = 34, cycles = 2, context_items = 3, tools = 1 },
}
out = rendered(vim.api.nvim_get_current_win())
has(out, "Chat Adapter", "chat adapter metadata is displayed")
has(out, "34", "chat token metadata is displayed")
has(out, "2", "chat cycle metadata is displayed")
has(out, "3", "chat context metadata is displayed")
has(out, "1", "chat tool metadata is displayed")

vim.api.nvim_win_set_buf(0, buf)
vim.bo[buf].buftype = "nofile"
vim.bo[buf].filetype = "help"
out = rendered(vim.api.nvim_get_current_win())
has(out, "HELP", "special buffers use their compact layout")

vim.bo[buf].buftype = ""
vim.bo[buf].filetype = "lua"
vim.cmd("vsplit")
local original_width = vim.api.nvim_win_get_width(0)
vim.api.nvim_win_set_width(0, 24)
local narrow_win = vim.api.nvim_get_current_win()
vim.b[buf].gitsigns_status_dict = { head = string.rep("long-branch", 8), added = 2, changed = 3, removed = 1 }
vim.api.nvim_buf_set_name(buf, "/tmp/" .. string.rep("x%", 30) .. ".lua")
local get_clients = vim.lsp.get_clients
vim.lsp.get_clients = function()
	return { { name = string.rep("long-lsp-name", 8), stop = function() end } }
end
local raw_narrow = statusline.render(narrow_win)
out = vim.api.nvim_eval_statusline(raw_narrow, { winid = narrow_win }).str
vim.lsp.get_clients = get_clients
assert(not raw_narrow:find("LSP", 1, true), "LSP context is removed from narrow statuslines")
assert(not raw_narrow:find("long-branch", 1, true), "raw statusline drops Git context in a narrow window")
has(raw_narrow, "DiagnosticError", "narrow raw statusline keeps diagnostics")
assert(vim.fn.strdisplaywidth(out) <= 24, "narrow statusline must fit target window width: " .. out)
has(out, "NORMAL", "24-column statusline keeps the mode visible")
has(out, "1:1", "24-column statusline keeps the ruler visible")
vim.api.nvim_win_set_width(0, original_width)

vim.api.nvim_win_set_width(narrow_win, 40)
vim.api.nvim_win_set_buf(narrow_win, chat_buf)
local raw_chat_narrow = statusline.render(narrow_win)
has(raw_chat_narrow, "NORMAL", "narrow chat layout preserves the mode")
has(raw_chat_narrow, "1:1", "narrow chat layout preserves the ruler")
assert(not raw_chat_narrow:find("Σ", 1, true), "narrow chat layout drops optional metadata")
vim.api.nvim_win_set_buf(narrow_win, buf)
local normal40 = vim.api.nvim_eval_statusline(statusline.render(narrow_win), { winid = narrow_win }).str
has(normal40, "NORMAL", "40-column statusline keeps the mode visible")
has(normal40, "1:1", "40-column statusline keeps the ruler visible")
vim.api.nvim_win_set_width(narrow_win, 24)

local active_win = vim.api.nvim_get_current_win()
local target_win
for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
	if candidate ~= active_win then
		target_win = candidate
		break
	end
end
assert(target_win, "test setup should have a second window")
local target_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_option(target_buf, "filetype", "help")
vim.api.nvim_win_set_buf(target_win, target_buf)
has(rendered(target_win), "HELP", "render(win) reads the requested target window")
local inactive = statusline.render(target_win)
assert(
	inactive:find("%#StatusLineNC#", 1, true),
	"render(win) uses inactive statusline highlight for a non-current window"
)

local laststatus = vim.o.laststatus
vim.api.nvim_buf_set_option(target_buf, "filetype", "lua")
vim.api.nvim_buf_set_option(target_buf, "buftype", "")
vim.lsp.get_clients = function()
	return { { name = "lsp-name", stop = function() end } }
end
vim.api.nvim_win_set_width(target_win, 40)
vim.o.laststatus = 3
local global_status = statusline.render(target_win)
vim.o.laststatus = 2
local local_status = statusline.render(target_win)
vim.lsp.get_clients = get_clients
assert(global_status:find("%#StatusLineNC#", 1, true), "global statusline retains non-current window colors")
has(global_status, "lsp-name", "laststatus=3 bases layout width on global columns")
assert(local_status:find("%#StatusLineNC#", 1, true), "laststatus=2 uses the target window statusline")
assert(not local_status:find("lsp-name", 1, true), "laststatus=2 bases layout width on the target window")
vim.o.laststatus = laststatus

vim.cmd("colorscheme default")
vim.wait(20)
assert(
	vim.api.nvim_get_hl(0, { name = "MayonSLModeFunction" }).bg ~= nil,
	"private highlights refresh after ColorScheme"
)

-- Resolve the highlight stack, as the screen does, for an inactive filename.
vim.api.nvim_set_hl(0, "StatusLine", { fg = "#ffffff", bg = "#111111" })
vim.api.nvim_set_hl(0, "StatusLineNC", { fg = "#888888", bg = "#222222" })
vim.api.nvim_exec_autocmds("ColorScheme", { pattern = "test" })
vim.wait(30)
local evaluated = vim.api.nvim_eval_statusline(statusline.render(target_win), { winid = target_win, highlights = true })
for _, span in ipairs(evaluated.highlights) do
	if span.group == "MayonSLText" then
		local background
		for _, name in ipairs(span.groups) do
			background = vim.api.nvim_get_hl(0, { name = name, link = false }).bg or background
		end
		assert(background == 0x222222, "inactive filename/ruler must inherit the inactive bar surface")
	end
end
print("statusline tests passed")
