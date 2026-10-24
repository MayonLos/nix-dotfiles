-- Local visual fixture for AI panels; no model request and no real CLI process.
require("lz.n").trigger_load({ "codecompanion.nvim", "claudecode.nvim", "sidekick.nvim", "edgy.nvim" })
local panels = require("mayon.ui.ai_panels")
local original_diff_add = vim.api.nvim_get_hl(0, { name = "DiffAdd" })
local original_diff_delete = vim.api.nvim_get_hl(0, { name = "DiffDelete" })
panels.setup()
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

local chat_buf = panels.open_fixture("chat")
assert(vim.bo[chat_buf].filetype == "codecompanion", "fixture must use a real CodeCompanion chat buffer")
vim.wait(30)
local lines = vim.api.nvim_buf_get_lines(chat_buf, 0, -1, false)
local transcript = table.concat(lines, "\n")
assert(transcript:find("## YOU", 1, true), "user fixture heading should use uppercase role")
assert(transcript:find("## DEEPSEEK", 1, true), "assistant fixture heading should show adapter")
local chat_win = vim.fn.win_findbuf(chat_buf)[1]
assert(chat_win, "CodeCompanion fixture must be visible in a window")
local previous_win = vim.api.nvim_get_current_win()
vim.g.statusline_winid = chat_win
assert(panels.winbar():find("deepseek%-v4%-flash"), "chat winbar should use the statusline window's resolved model")
vim.g.statusline_winid = nil
vim.api.nvim_set_current_win(previous_win)
local marks = vim.api.nvim_buf_get_extmarks(chat_buf, -1, 0, -1, { details = true })
assert(#marks > 0, "CodeCompanion fixture should have panel decorations")
assert(panels.winbar(chat_buf):find("DeepSeek", 1, true), "chat panel should identify its adapter")

local terminal_buf = panels.open_fixture("terminal")
assert(vim.bo[terminal_buf].buftype == "terminal", "terminal fixture must use Neovim's terminal buffer")
assert(vim.b[terminal_buf].mayon_ai_fixture, "terminal fixture must be explicitly offline")
assert(
	panels.winbar(terminal_buf):find("OFFLINE FIXTURE", 1, true),
	"terminal container should identify its fixture status"
)

vim.api.nvim_buf_delete(chat_buf, { force = true })
vim.api.nvim_buf_delete(terminal_buf, { force = true })
