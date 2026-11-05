-- Local visual fixture for AI panels; no model request and no real CLI process.
vim.o.columns, vim.o.lines = 160, 50
local codecompanion_load_columns = vim.o.columns
local float_before = {}
for _, name in ipairs({ "NormalFloat", "FloatBorder", "FloatTitle" }) do
	float_before[name] = vim.api.nvim_get_hl(0, { name = name, link = false })
end
require("lz.n").trigger_load({ "codecompanion.nvim", "claudecode.nvim", "edgy.nvim" })
local panels = require("mayon.ui.ai_panels")
local original_diff_add = vim.api.nvim_get_hl(0, { name = "DiffAdd" })
local original_diff_delete = vim.api.nvim_get_hl(0, { name = "DiffDelete" })
panels.setup()
-- Chat decoration never hooks keystrokes globally; only chat buffers get
-- buffer-local text-change hooks.
local events = {}
for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ group = "MayonAIPanels" })) do
	for _, event in ipairs(type(autocmd.event) == "table" and autocmd.event or { autocmd.event }) do
		events[event] = true
	end
end
assert(not events.TextChanged and not events.TextChangedI, "AI decoration must not hook global text-change events")
for name, value in pairs(float_before) do
	assert(
		vim.deep_equal(value, vim.api.nvim_get_hl(0, { name = name, link = false })),
		"AI lazy loading recolored " .. name
	)
end
local ai_surface = vim.api.nvim_get_hl(0, { name = "MayonAIPanel", link = false })
assert(
	ai_surface.bg == tonumber(require("mayon.generated").palette.bg:sub(2), 16),
	"AI split panels should use the editor canvas color"
)
assert(
	vim.deep_equal(original_diff_add, vim.api.nvim_get_hl(0, { name = "DiffAdd" })),
	"AI setup must not recolor global DiffAdd"
)
assert(
	vim.deep_equal(original_diff_delete, vim.api.nvim_get_hl(0, { name = "DiffDelete" })),
	"AI setup must not recolor global DiffDelete"
)
vim.api.nvim_exec_autocmds("ColorScheme", {})
assert(
	vim.api.nvim_get_hl(0, { name = "CodeCompanionChatTool" }).fg,
	"AI highlights should be restored after colorscheme changes"
)

local diff_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(diff_buf, "/tmp/a%name.nix")
vim.b[diff_buf].claudecode_diff_tab_name = "/tmp/a%name.nix"
local diff_bar = panels.diff_winbar(diff_buf)
assert(diff_bar:find("a%%name.nix", 1, true), "dynamic winbar filenames must escape statusline percent signs")
assert(diff_bar:find("MayonAIRemoved", 1, true), "reject action should use the red diff color")
vim.api.nvim_buf_delete(diff_buf, { force = true })

assert(codecompanion_load_columns >= 120, "CodeCompanion fixture must load while the editor is wide")
vim.o.columns = 91
local chat_buf = panels.open_fixture("chat")
assert(vim.bo[chat_buf].filetype == "codecompanion", "fixture must use a real CodeCompanion chat buffer")
vim.wait(30)
local lines = vim.api.nvim_buf_get_lines(chat_buf, 0, -1, false)
local transcript = table.concat(lines, "\n")
assert(transcript:find("## YOU", 1, true), "user fixture heading should use uppercase role")
assert(transcript:find("## DEEPSEEK", 1, true), "assistant fixture heading should show adapter")
local chat_win = vim.fn.win_findbuf(chat_buf)[1]
assert(chat_win, "CodeCompanion fixture must be visible in a window")
local chat_config = vim.api.nvim_win_get_config(chat_win)
assert(chat_config.relative ~= "", "CodeCompanion should open as an on-demand float after a narrow resize")
assert(
	vim.api.nvim_win_get_width(chat_win) <= vim.o.columns - 4,
	"CodeCompanion float should stay within the current editor width"
)
assert(chat_config.border[1] == "╭", "CodeCompanion float should use the shared rounded border")
assert(vim.w[chat_win].mayon_ai_panel == true, "chat window must be marked as an AI panel")
local surface = tonumber(require("mayon.generated").palette.bg:sub(2), 16)
assert(vim.api.nvim_get_hl(0, { name = "FloatBorder", link = false }).bg == surface)
assert(vim.api.nvim_get_hl(0, { name = "FloatTitle", link = false }).bg == surface)
assert(
	vim.wo[chat_win].winhighlight:find("Normal:NormalFloat", 1, true),
	"CodeCompanion float should use the editor canvas"
)
assert(panels.winbar(chat_buf):find("DeepSeek", 1, true), "CodeCompanion float should retain its provider label")
local previous_win = vim.api.nvim_get_current_win()
vim.g.statusline_winid = chat_win
assert(panels.winbar():find("deepseek%-v4%-flash"), "chat winbar should use the statusline window's resolved model")
vim.g.statusline_winid = nil
vim.api.nvim_set_current_win(previous_win)
local marks = vim.api.nvim_buf_get_extmarks(chat_buf, -1, 0, -1, { details = true })
assert(#marks > 0, "CodeCompanion fixture should have panel decorations")
assert(panels.winbar(chat_buf):find("DeepSeek", 1, true), "chat panel should identify its adapter")
if not vim.env.DEEPSEEK_API_KEY or vim.env.DEEPSEEK_API_KEY == "" then
	assert(
		panels.winbar(chat_buf):find("未配置密钥", 1, true),
		"unconfigured providers must not show as connected"
	)
end

-- Typed or streamed text is redecorated before the reply is done, from a
-- buffer-local hook coalesced to one pass per tick.
local local_hooks = vim.api.nvim_get_autocmds({ group = "MayonAIPanelsChat", buffer = chat_buf })
local hooked_events = {}
for _, autocmd in ipairs(local_hooks) do
	hooked_events[autocmd.event] = true
end
assert(hooked_events.TextChanged and hooked_events.TextChangedI, "chat buffers need buffer-local text-change hooks")
local original_decorate = panels.decorate_chat
vim.api.nvim_buf_clear_namespace(chat_buf, vim.api.nvim_get_namespaces().MayonAIPanels, 0, -1)
local line_count = vim.api.nvim_buf_line_count(chat_buf)
vim.api.nvim_buf_set_lines(chat_buf, line_count, line_count, false, { "", "## YOU", "", "streamed text" })
vim.api.nvim_exec_autocmds("TextChanged", { buffer = chat_buf, modeline = false })
vim.api.nvim_exec_autocmds("TextChangedI", { buffer = chat_buf, modeline = false })
vim.wait(30)
assert(
	#vim.api.nvim_buf_get_extmarks(chat_buf, vim.api.nvim_get_namespaces().MayonAIPanels, 0, -1, {}) > 0,
	"text changes in a chat buffer must redecorate it"
)
assert(panels.decorate_chat == original_decorate, "decorate_chat export must stay stable")

-- Adapter/model switches invalidate the cached provider label.
assert(panels.winbar(chat_buf):find("deepseek%-v4%-flash"), "chat winbar should show the default model")
local adapter_utils = require("codecompanion.adapters.utils")
local original_resolve = adapter_utils.resolve_model
adapter_utils.resolve_model = function()
	return "switched-model"
end
vim.api.nvim_exec_autocmds("User", { pattern = "CodeCompanionChatModel", data = { bufnr = chat_buf } })
vim.wait(30)
assert(panels.winbar(chat_buf):find("switched-model", 1, true), "ChatModel must invalidate the provider cache")
adapter_utils.resolve_model = original_resolve
vim.api.nvim_exec_autocmds("User", { pattern = "CodeCompanionChatAdapter", data = { bufnr = chat_buf } })
vim.wait(30)
assert(panels.winbar(chat_buf):find("deepseek%-v4%-flash"), "ChatAdapter must invalidate the provider cache")

local terminal_buf = panels.open_fixture("terminal")
assert(vim.bo[terminal_buf].buftype == "terminal", "terminal fixture must use Neovim's terminal buffer")
assert(vim.b[terminal_buf].mayon_ai_fixture, "terminal fixture must be explicitly offline")
local terminal_win = vim.fn.win_findbuf(terminal_buf)[1]
assert(terminal_win and vim.w[terminal_win].mayon_ai_panel == true, "AI terminal window must be marked")
assert(
	panels.winbar(terminal_buf):find("OFFLINE FIXTURE", 1, true),
	"terminal container should identify its fixture status"
)

-- The Claude connection poll runs only while an AI panel is visible.
assert(panels.poll_active(), "Claude status poll should run while an AI panel is visible")
vim.api.nvim_buf_delete(chat_buf, { force = true })
vim.api.nvim_buf_delete(terminal_buf, { force = true })
assert(
	vim.wait(1500, function()
		return not panels.poll_active()
	end, 50),
	"Claude status poll must stop when no AI panel is visible"
)
