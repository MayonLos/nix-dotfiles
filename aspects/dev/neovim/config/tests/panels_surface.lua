vim.api.nvim_exec_autocmds("User", { pattern = "MayonVeryLazy" })
local floats = require("mayon.ui.floats")
floats.setup()
require("mayon.features.completion_ui").setup()
require("lz.n").trigger_load("neogit")
local palette = require("mayon.generated").palette
local neogit_border = vim.api.nvim_get_hl(0, { name = "NeogitFloatBorder", link = false })
local float_border = vim.api.nvim_get_hl(0, { name = "FloatBorder", link = false })
assert(
	vim.api.nvim_get_hl(0, { name = "EndOfBuffer", link = false }).bg == nil,
	"empty rows must inherit the floating or inactive window background"
)
assert(neogit_border.fg == float_border.fg and neogit_border.bg == float_border.bg)
assert(
	vim.api.nvim_get_hl(0, { name = "NeogitNormalFloat", link = false }).bg == tonumber(palette.bg:sub(2), 16),
	"Neogit's private namespace must retain the unified editor floating surface"
)
-- Every opaque layer (title chunks, virtual padding and parent layouts too)
-- uses the editor canvas. A same-colored border alone leaves dark rectangles.
for _, group in ipairs({
	"NormalFloat",
	"FloatBorder",
	"FloatTitle",
	"Pmenu",
	"PmenuBorder",
	"MayonPopup",
	"SnacksPickerBox",
	"SnacksPickerPreview",
	"MayonPickerCount",
	"MayonNotificationBody",
	"SnacksNotifierIconInfo",
	"SnacksNotifierIconError",
}) do
	assert(
		vim.api.nvim_get_hl(0, { name = group, link = false }).bg == tonumber(palette.bg:sub(2), 16),
		group .. " must share the editor canvas"
	)
end
local opts = floats.options("hover")
assert(opts.border == "rounded" and opts.title_pos == "center" and opts.title:find("hover · ", 1, true))
local buf, win = vim.lsp.util.open_floating_preview(
	{ "```lua", "function example()", "```", "Documentation" },
	"markdown",
	vim.tbl_extend("force", opts, { focus_id = "textDocument/hover" })
)
local hover_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
assert(vim.api.nvim_win_get_config(win).title[1][1]:find("hover", 1, true))
assert(vim.api.nvim_win_get_config(win).title_pos == "center")
assert(vim.wo[win].winhighlight:find("NormalFloat", 1, true))
assert(not vim.wo[win].spell, "Markdown hover should not underline API identifiers as misspellings")
local padding_ns = vim.api.nvim_create_namespace("MayonFloatPadding")
assert(#vim.api.nvim_buf_get_extmarks(buf, padding_ns, 0, -1, {}) >= 4, "hover should have inline one-cell padding")
assert(
	vim.deep_equal(vim.api.nvim_buf_get_lines(buf, 0, -1, false), hover_lines),
	"float padding must not alter the documentation buffer text"
)
assert(
	table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n"):find("─", 1, true),
	"hover should separate signature from prose"
)
vim.api.nvim_win_close(win, true)
-- Padding must be included in geometry, including max-width wrapped text.
for _, limit in ipairs({ 64, 24 }) do
	local text = string.rep("x", 40)
	local preview_buf, preview_win = vim.lsp.util.open_floating_preview({ text }, "text", {
		focus_id = "textDocument/hover",
		max_width = limit,
		border = "rounded",
	})
	local dim = vim.api.nvim_win_get_config(preview_win)
	local displayed = vim.api.nvim_win_text_height(preview_win, {}).all
	assert(dim.width <= limit and dim.height >= displayed, "padding caused the final documentation row to be clipped")
	if limit == 64 then
		assert(dim.width >= 42 and displayed == 1, "one padded line should fit without wrapping")
	end
	assert(vim.api.nvim_buf_get_lines(preview_buf, 0, 1, false)[1] == text)
	vim.api.nvim_win_close(preview_win, true)
end
local docs = vim.api.nvim_create_buf(false, true)
local docs_lines = { "```lua", "function documented()", "```", "Documentation" }
vim.api.nvim_buf_set_lines(docs, 0, -1, false, docs_lines)
local docs_win = vim.api.nvim_open_win(
	docs,
	false,
	{ relative = "editor", row = 3, col = 2, width = 40, height = 5, style = "minimal" }
)
local original_complete_info = vim.fn.complete_info
local original_pumvisible = vim.fn.pumvisible
vim.fn.pumvisible = function()
	return 1
end
vim.fn.complete_info = function()
	return { preview_winid = docs_win, selected = -1, items = {} }
end
vim.api.nvim_exec_autocmds("CompleteChanged", {})
assert(
	vim.wait(200, function()
		return vim.bo[docs].filetype == "markdown"
	end, 10),
	"completion Markdown should use the same document renderer as hover"
)
vim.fn.complete_info = original_complete_info
vim.fn.pumvisible = original_pumvisible
assert(
	vim.deep_equal(vim.api.nvim_buf_get_lines(docs, 0, -1, false), docs_lines),
	"completion document styling changed its text"
)
vim.api.nvim_win_close(docs_win, true)
vim.api.nvim_buf_delete(docs, { force = true })
local notifier = require("snacks").config.notifier
assert(
	notifier.top_down and type(notifier.style) == "function" and notifier.timeout >= 2500 and notifier.timeout <= 4000,
	"notifications should render at upper right with native custom style"
)
local b = vim.api.nvim_create_buf(false, true)
local ctx = { opts = {}, ns = vim.api.nvim_create_namespace("MayonNotificationTest") }
notifier.style(b, { level = "warn", title = "Saved", msg = "formatter · 12ms" }, ctx)
assert(
	ctx.opts.border == "rounded" and ctx.opts.title_pos == "center",
	"notification should share the rounded frame and centered title"
)
assert(vim.api.nvim_buf_get_lines(b, 0, 1, false)[1] == "formatter · 12ms")
local snacks_notifier = Snacks.notifier
local old_history, old_hide = snacks_notifier.get_history, snacks_notifier.hide
local hidden = {}
local cap_entries = {
	{ id = 5, layout = { top = 10 } },
	{ id = 4, layout = { top = 20 } },
	{ id = 3, layout = { top = 30 } },
	{ id = 2 },
	{ id = 1 },
}
snacks_notifier.get_history = function()
	return cap_entries
end
snacks_notifier.hide = function(id)
	hidden[#hidden + 1] = id
end
require("mayon.ui.notifications").render(b, { level = "warn", title = "Saved", msg = "formatter · 12ms" }, ctx)
vim.wait(50, function()
	return #hidden == 2
end, 5)
assert(vim.deep_equal(hidden, { 2, 1 }), "notification cap should hide all but the latest three")
-- Hidden-from-history notifications still count toward the visible cap.
hidden = {}
snacks_notifier.get_history = function()
	return {}
end
for index = 21, 24 do
	require("mayon.ui.notifications").filter({ id = index, added = index, level = "info", msg = "no history" })
end
require("mayon.ui.notifications").cap_visible()
assert(vim.deep_equal(hidden, { 21 }), "history=false notifications bypassed the three-card limit")
snacks_notifier.get_history, snacks_notifier.hide = old_history, old_hide
assert(
	not cap_entries[1].layout.top and not cap_entries[3].layout.top,
	"retained cards must close the gaps left by hidden notifications"
)
vim.api.nvim_buf_delete(b, { force = true })
local c = require("mayon.generated").palette
assert(
	vim.api.nvim_get_hl(0, { name = "CursorLine", link = false }).bg ~= tonumber(c.bg:sub(2), 16),
	"current source line should have a subtle background"
)
local indent = require("snacks").config.indent
assert(indent.indent.enabled and indent.animate.enabled == false, "quiet indent guide should be static")
assert(indent.scope.only_current)
local docs_events = vim.api.nvim_get_autocmds({ group = "MayonCompletionUI", event = "CompleteChanged" })
assert(#docs_events == 1, "native completion documentation must have a single presentation owner")

assert(require("snacks").config.lazygit.configure == false, "lazygit CLI palette belongs to the CLI feature")
for _, name in ipairs({ "input", "terminal", "lazygit" }) do
	assert(require("snacks").config[name].win.backdrop == false, name .. " must not add a second dimmed rectangle")
end
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
assert(surface_config.title_pos == "center", "secondary float titles should be centered")
assert(vim.wo[surface_win].winhighlight:find("NormalFloat", 1, true))
assert(
	vim.wo[surface_win].winhighlight:find("EndOfBuffer:NormalFloat", 1, true),
	"minimal float empty rows must use its own canvas instead of a cleared highlight"
)
vim.api.nvim_win_close(surface_win, true)
vim.api.nvim_buf_delete(surface_buf, { force = true })
local old_hlsearch = vim.o.hlsearch
vim.o.hlsearch = false
assert(extras.searchcount() == "", "search count should stay hidden when search highlighting is off")
vim.o.hlsearch = old_hlsearch
