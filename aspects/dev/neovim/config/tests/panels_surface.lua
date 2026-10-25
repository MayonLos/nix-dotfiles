vim.api.nvim_exec_autocmds("User", { pattern = "MayonVeryLazy" })
local floats = require("mayon.ui.floats")
floats.setup()
local opts = floats.options("hover")
assert(opts.border == "rounded" and opts.title:find("hover · ", 1, true))
local buf, win = vim.lsp.util.open_floating_preview(
	{ "```lua", "function example()", "```", "Documentation" },
	"markdown",
	vim.tbl_extend("force", opts, { focus_id = "textDocument/hover" })
)
assert(vim.api.nvim_win_get_config(win).title[1][1]:find("hover", 1, true))
assert(vim.wo[win].winhighlight:find("NormalFloat", 1, true))
assert(
	table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):find("─", 1, true),
	"hover should separate signature from prose"
)
vim.api.nvim_win_close(win, true)
local notifier = require("snacks").config.notifier
assert(
	notifier.top_down and type(notifier.style) == "function",
	"notifications should render at upper right with native custom style"
)
local b = vim.api.nvim_create_buf(false, true)
local ctx = { opts = {}, ns = vim.api.nvim_create_namespace("MayonNotificationTest") }
notifier.style(b, { level = "warn", title = "Saved", msg = "formatter · 12ms" }, ctx)
assert(
	ctx.opts.border[8][1] == "▎" and ctx.opts.title == nil,
	"notification should use a level rail without a large icon"
)
assert(vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] == "Saved · WARN")
vim.api.nvim_buf_delete(b, { force = true })
local c = require("mayon.generated").palette
assert(
	vim.api.nvim_get_hl(0, { name = "CursorLine", link = false }).bg ~= tonumber(c.bg:sub(2), 16),
	"current source line should have a subtle background"
)
assert(require("snacks").config.indent.indent.enabled == false, "only active scope may draw an indent guide")
assert(require("snacks").config.indent.scope.only_current)
local rail = vim.api.nvim_get_autocmds({ group = "MayonCompletionDocs", event = "CompleteChanged" })
assert(#rail == 2, "completion documentation and selected row must both be styled")

assert(require("snacks").config.lazygit.configure == false, "lazygit CLI palette belongs to the CLI feature")
local terminal = require("snacks").terminal({ "sh", "-c", "sleep 30" }, {
	win = { style = "float", border = "rounded", title = " terminal " },
})
assert(terminal, "native terminal fixture did not open")
vim.wait(200)
local terminal_win = terminal.win
assert(terminal_win and vim.api.nvim_win_is_valid(terminal_win))
assert(vim.api.nvim_win_get_config(terminal_win).relative ~= "", "Edgy swallowed the terminal float")
assert(vim.api.nvim_win_get_config(terminal_win).border, "terminal float lost its border")
terminal:close()

local extras = require("mayon.ui.extras")
local surface_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(surface_buf, "/tmp/surface-help.txt")
vim.bo[surface_buf].filetype = "help"
local surface_win = vim.api.nvim_open_win(surface_buf, false, {
	relative = "editor",
	row = 1,
	col = 2,
	width = 30,
	height = 2,
	style = "minimal",
	border = "none",
})
extras.style_float(surface_win)
local surface_config = vim.api.nvim_win_get_config(surface_win)
assert(vim.inspect(surface_config.border):find("╭", 1, true), "secondary floats should use rounded borders")
assert(
	vim.inspect(surface_config.title):find("Help · surface-help.txt", 1, true),
	"secondary float should carry title and source: " .. vim.inspect(surface_config.title)
)
assert(vim.wo[surface_win].winhighlight:find("NormalFloat", 1, true))
vim.api.nvim_win_close(surface_win, true)
vim.api.nvim_buf_delete(surface_buf, { force = true })
local old_hlsearch = vim.o.hlsearch
vim.o.hlsearch = false
assert(extras.searchcount() == "", "search count should stay hidden when search highlighting is off")
vim.o.hlsearch = old_hlsearch
