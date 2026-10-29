local capture = assert(_G.MayonSelfcheck, "selfcheck_capture.lua must run before startup via --cmd")
capture.hook_notify()
local function phase(name, fn)
	capture.phase = name
	fn()
	vim.wait(150)
	capture.hook_notify()
end
phase("deferred plugins", function()
	vim.api.nvim_exec_autocmds("UIEnter", {})
	vim.api.nvim_exec_autocmds("User", { pattern = "MayonVeryLazy" })
	require("mayon.features.ai_completion").set("off")
end)
local root = vim.fn.tempname()
vim.fn.mkdir(root .. "/.git", "p")
vim.fn.writefile({ "# Fixture", "", "offline selfcheck" }, root .. "/README.md")
vim.fn.writefile(
	{ "int square(int value) { return value * value; }", "int main(void) { return square(2); }" },
	root .. "/main.c"
)
vim.cmd.cd(root)
phase("first file", function()
	vim.cmd.edit(root .. "/main.c")
end)
local source = vim.api.nvim_get_current_buf()
phase("all plugin configurations", function()
	for _, domain in ipairs({
		"completion",
		"languages",
		"lua",
		"treesitter",
		"editing",
		"formatting",
		"lint",
		"git",
		"navigation",
		"utility",
		"markdown",
		"ai",
		"decorations",
		"layout",
	}) do
		for _, spec in ipairs(require("mayon.plugins." .. domain)) do
			if spec.enabled ~= false then
				require("lz.n").trigger_load(spec[1])
			end
		end
	end
end)
phase("outline layouts", function()
	vim.o.columns = 180
	vim.o.lines = 50
	vim.api.nvim_set_current_buf(source)
	vim.cmd.vsplit()
	vim.cmd.tabnew(root .. "/README.md")
	vim.cmd.tabprevious()
	vim.o.columns = 90
	vim.api.nvim_exec_autocmds("VimResized", {})
	vim.wait(100)
	assert(not require("mayon.ui.outline").is_open(), "narrow outline remained open")
	vim.o.columns = 180
	vim.api.nvim_exec_autocmds("VimResized", {})
end)
phase("tools", function()
	vim.cmd.help("help")
	vim.cmd.wincmd("p")
	vim.fn.setqflist(
		{},
		"r",
		{ title = "selfcheck", items = { { filename = root .. "/main.c", lnum = 1, text = "fixture" } } }
	)
	vim.cmd.copen()
	vim.cmd.cclose()
	vim.api.nvim_set_current_buf(source)
	local picker = Snacks.picker.files({ cwd = root, show_delay = 0 })
	vim.wait(150)
	picker:close()
	local explorer = Snacks.explorer({ cwd = root })
	vim.wait(150)
	explorer:close()
end)
phase("session restore", function()
	vim.api.nvim_set_current_buf(source)
	local sessions = require("mayon.features.sessions")
	sessions.setup()
	assert(sessions.save(true), "isolated session save failed")
	sessions.load()
end)
phase("health integrations", function()
	assert(Snacks.config.picker.enabled and Snacks.config.input.enabled and Snacks.config.scope.enabled)
	assert(vim.ui.select == Snacks.picker.select, "Snacks select integration was replaced")
	assert(pcall(require, "which-key"), "which-key runtime missing")
	assert(not vim.tbl_contains(Snacks.image.langs(), "norg"), "unsupported norg image query installed")
end)
-- Inventory all runtime surfaces, including buffer mappings and which-key-only
-- group entries. Invocation policies live in selfcheck_actions.lua; inventory
-- is persisted even when a new unclassified mapping makes that audit fail.
phase("inventory", function()
	local maps = {}
	for _, mode in ipairs({ "n", "i", "v", "x", "s", "o", "c", "t", "l" }) do
		for _, map in ipairs(vim.api.nvim_get_keymap(mode)) do
			maps[#maps + 1] =
				{ mode = mode, lhs = map.lhs, desc = map.desc, rhs = map.rhs, callback = map.callback ~= nil }
		end
		for _, buf in ipairs(vim.api.nvim_list_bufs()) do
			for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
				maps[#maps + 1] = {
					mode = mode,
					buffer = buf,
					lhs = map.lhs,
					desc = map.desc,
					rhs = map.rhs,
					callback = map.callback ~= nil,
				}
			end
		end
	end
	local commands = vim.api.nvim_get_commands({ builtin = false })
	for _, command in pairs(commands) do
		command.script_id = nil
	end
	capture.coverage = { maps = maps, commands = commands, which_key = require("mayon.ui.whichkey").config().spec }
end)
local errors = capture.finish()
assert(#errors == 0, "selfcheck ERRORs: " .. vim.inspect(errors))
print(
	"selfcheck passed: startup, all plugin setup, outline, tools, session, integration health, mapping/command inventory"
)
