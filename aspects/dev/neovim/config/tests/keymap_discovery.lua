-- Load the editor's registered mappings offline, then validate the public
-- which-key v3 spec and the descriptions that are visible to users.
local source = debug.getinfo(1, "S").source:sub(2)
local config_root = vim.fs.dirname(vim.fs.dirname(source))
vim.opt.rtp:prepend(config_root)
vim.cmd.packadd("nvim-lspconfig")
vim.api.nvim_exec_autocmds("UIEnter", {})
vim.api.nvim_exec_autocmds("BufReadPre", {})
vim.bo.filetype = "text"
local ai_completion = require("mayon.features.ai_completion")
ai_completion.set("off")
ai_completion.copilot_setup()

require("mayon.config.keymaps").setup()
vim.api.nvim_exec_autocmds("User", { pattern = "MayonVeryLazy" })
local domains = {
	"snacks",
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
}
local plugins = {}
for _, domain in ipairs(domains) do
	for _, spec in ipairs(require("mayon.plugins." .. domain)) do
		if spec.enabled ~= false then
			plugins[#plugins + 1] = spec[1]
		end
	end
end
require("lz.n").trigger_load(plugins)
vim.wait(100)
assert(not vim.g.mayon_load_error, vim.g.mayon_load_error)

local lsp = require("mayon.lsp")
local enable = vim.lsp.enable
vim.lsp.enable = function() end
lsp.setup()
vim.lsp.enable = enable
local buf = vim.api.nvim_create_buf(true, false)
local old_get_client = vim.lsp.get_client_by_id
vim.lsp.get_client_by_id = function(id)
	if id == -1 then
		return {
			id = id,
			name = "offline-fixture",
			supports_method = function()
				return false
			end,
		}
	end
	return old_get_client(id)
end
vim.api.nvim_exec_autocmds("LspAttach", { buffer = buf, data = { client_id = -1 } })
vim.lsp.get_client_by_id = old_get_client

local whichkey = require("mayon.ui.whichkey")
whichkey.setup()
vim.api.nvim_exec_autocmds("VimEnter", {})
vim.wait(100)
local config = whichkey.config()
assert(config.win.border == "single" and config.win.row == -1, "which-key should keep a bottom single-line surface")
assert(config.win.title == true, "which-key should derive its title from the active prefix")
local geometry = whichkey.geometry
local wide = geometry(1706)
local normal = geometry(195)
local medium = geometry(160)
local narrow = geometry(80)
local small = geometry(50)
local tiny = geometry(40)
assert(wide.width == 118 and wide.col == 794 and wide.columns == 4, "which-key should cap and center its wide layout")
assert(normal.width == 118 and normal.col == 38, "which-key should stay centered at the usual window size")
assert(medium.width == 110 and medium.col == 25, "which-key should scale with medium windows")
assert(narrow.width == 55 and narrow.col == 12 and narrow.columns == 3, "which-key should adapt narrow layouts")
assert(small.width == 34 and small.col == 8 and small.columns == 2, "which-key should reduce columns on small windows")
assert(tiny.width == 27 and tiny.col == 6 and tiny.columns == 1, "which-key should use one column on tiny windows")
assert(config.win.width == geometry(vim.o.columns).width)
assert(config.win.col == geometry(vim.o.columns).col and config.layout.spacing == 2)
assert(config.win.height.min == 4 and config.win.height.max == 10, "which-key height should remain compact")
assert(type(config.delay) == "function", "which-key delay should be explicit and context-aware")
assert(
	config.delay({}) == 200 and config.delay({ plugin = "fixture" }) == 0,
	"which-key delay should be 200ms or immediate for plugins"
)
assert(
	config.show_help == false and config.show_keys == false and config.expand == 0,
	"which-key should hide popup noise"
)
assert(config.filter({ desc = "Find Files" }), "described mappings should remain visible")
assert(not config.filter({ desc = "" }) and not config.filter({}), "undescribed mappings should stay hidden")

local expected_groups = {
	Search = true,
	Git = true,
	LSP = true,
	Debug = true,
	AI = true,
	Terminal = true,
	UI = true,
	Files = true,
	Project = true,
	Run = true,
	List = true,
	Multicursor = true,
	Buffers = true,
	Quit = true,
	Notes = true,
	Code = true,
}
local groups = {}
for _, item in ipairs(config.spec) do
	assert(item.order == nil, "which-key spec must use supported manual insertion order")
	if item.group then
		assert(expected_groups[item.group], "unexpected which-key group: " .. item.group)
		assert(not groups[item.group], "duplicate which-key group: " .. item.group)
		groups[item.group] = true
		assert(
			type(item.icon) == "table" and item.icon.icon and item.icon.hl == "WhichKeyIcon",
			"group icon lacks the shared color"
		)
	end
end
assert(vim.deep_equal(groups, expected_groups), "which-key group set is incomplete: " .. vim.inspect(groups))
assert(config.icons.mappings and config.icons.colors == false, "group icons should use the shared highlight")
assert(config.plugins.marks and config.plugins.registers, "mark, register, quote and @ hints should be enabled")
assert(config.plugins.spelling.enabled, "z= spelling help should remain discoverable")
for _, preset in ipairs({ "operators", "motions", "text_objects", "windows", "nav", "z", "g" }) do
	assert(config.plugins.presets[preset], "missing native key hint preset: " .. preset)
end

local palette = require("mayon.generated").palette
local icon_hl = vim.api.nvim_get_hl(0, { name = "WhichKeyIcon", link = false })
assert(icon_hl.fg == tonumber(palette.blue:sub(2), 16), "all group icons should share the One Dark blue")
for _, name in ipairs({
	"WhichKey",
	"WhichKeyDesc",
	"WhichKeyGroup",
	"WhichKeySeparator",
	"WhichKeyTitle",
	"WhichKeyNormal",
	"WhichKeyIcon",
	"WhichKeyBorder",
}) do
	local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
	assert(hl.bg == tonumber(palette.deep:sub(2), 16), "which-key surface must match One Dark deep: " .. name)
end

-- Descriptions are short English action labels. Inspect all modes after lazy
-- plugin keymaps and the synthetic LSP attachment have been registered. The
-- built-in which-key presets use `:help ...` documentation labels by design.
local action_verbs = {
	Accept = true,
	Add = true,
	Apply = true,
	Browse = true,
	Build = true,
	Clear = true,
	Clean = true,
	Close = true,
	Collect = true,
	Compare = true,
	Continue = true,
	Cycle = true,
	Create = true,
	Delete = true,
	Debug = true,
	Disconnect = true,
	Disable = true,
	Dismiss = true,
	Draft = true,
	Enable = true,
	Explain = true,
	Find = true,
	Focus = true,
	Format = true,
	Jump = true,
	Inspect = true,
	Load = true,
	List = true,
	Move = true,
	Open = true,
	Pause = true,
	Pick = true,
	Preview = true,
	Refresh = true,
	Reject = true,
	Remove = true,
	Rename = true,
	Reset = true,
	Resume = true,
	Resize = true,
	Restart = true,
	Review = true,
	Run = true,
	Save = true,
	Search = true,
	Select = true,
	Set = true,
	Send = true,
	Show = true,
	Skip = true,
	Step = true,
	Stage = true,
	Swap = true,
	Switch = true,
	Toggle = true,
	Terminate = true,
	Trigger = true,
	Write = true,
}
local descriptions, keymaps = {}, 0
for _, mode in ipairs({ "n", "x", "o", "i", "c", "t" }) do
	for _, mapping in ipairs(vim.api.nvim_get_keymap(mode)) do
		if
			mapping.desc
			and mapping.desc ~= ""
			and (mapping.sid >= 0 or mapping.lhs:match("^ "))
			and not mapping.desc:match("^:help ")
			and not mapping.lhs:match("^<Plug>")
			and not (mapping.rhs or ""):match("^<Plug>")
		then
			keymaps = keymaps + 1
			local desc = mapping.desc
			assert(
				#desc <= 28,
				("description exceeds 28 characters: %s (%d), %s %s; mapping=%s; config=%s; ai=%s"):format(
					desc,
					#desc,
					mode,
					mapping.lhs,
					vim.inspect(mapping),
					vim.env.NVIM_CONFIG_DIR,
					vim.inspect(vim.api.nvim_get_runtime_file("lua/mayon/plugins/ai.lua", true))
				)
			)
			assert(
				desc:match("^[A-Z][A-Za-z0-9 '&/()+%-]*$"),
				"description is not concise English title case: " .. desc
			)
			local verb = desc:match("^(%S+)")
			assert(action_verbs[verb], "description must start with an action verb: " .. desc)
			descriptions[desc] = true
		end
	end
	for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(buf, mode)) do
		if
			mapping.desc
			and mapping.desc ~= ""
			and (mapping.sid >= 0 or mapping.lhs:match("^ "))
			and not mapping.desc:match("^:help ")
			and not mapping.lhs:match("^<Plug>")
			and not (mapping.rhs or ""):match("^<Plug>")
		then
			keymaps = keymaps + 1
			local desc = mapping.desc
			assert(#desc <= 28, ("description exceeds 28 characters: %s (%d)"):format(desc, #desc))
			assert(
				desc:match("^[A-Z][A-Za-z0-9 '&/()+%-]*$"),
				"description is not concise English title case: " .. desc
			)
			local verb = desc:match("^(%S+)")
			assert(action_verbs[verb], "description must start with an action verb: " .. desc)
			descriptions[desc] = true
		end
	end
end
assert(keymaps >= 80, "too few mappings were inspected: " .. keymaps)

-- A post-registration keymap table cannot reveal overwritten registrations.
-- Check the effective callback instead, after all lazy domains and the fixture
-- LSP attachment above. Include both global and buffer-local lookup contexts.
local contexts = { vim.api.nvim_get_current_buf(), buf }
local function effective(lhs, context)
	return vim.api.nvim_buf_call(context, function()
		return vim.fn.maparg(lhs, "n", false, true)
	end)
end
local function assert_owner(lhs, callback)
	for _, context in ipairs(contexts) do
		local mapping = effective(lhs, context)
		assert(mapping.callback == callback, "unexpected final callback: " .. lhs .. " in buffer " .. context)
		assert(mapping.noremap == 1, "critical mapping must not remap: " .. lhs)
	end
end
local debug_spec = require("mayon.plugins.utility")[1]
assert(debug_spec[1] == "nvim-dap")
-- lz.n intentionally retains each first-key wrapper after trigger_load().
-- Replay the real key with only action boundaries stubbed, then compare the
-- installed callback identity. No debugger, input prompt or panel is opened.
local boundaries = {
	["dap"] = {
		"continue",
		"toggle_breakpoint",
		"step_over",
		"step_into",
		"step_out",
		"disconnect",
		"terminate",
		"run_to_cursor",
		"restart",
		"run_last",
		"clear_breakpoints",
		"pause",
	},
	["mayon.features.debug"] = { "breakpoint", "select" },
	["dap-view"] = { "toggle", "open", "jump_to_view", "add_expr" },
	["dap.ui.widgets"] = { "hover" },
	["mayon.features.java_debug"] = { "test_nearest_method", "test_class" },
}
local restore = {}
for name, methods in pairs(boundaries) do
	local module = require(name)
	for _, method in ipairs(methods) do
		restore[#restore + 1] = { module, method, module[method] }
		module[method] = function() end
	end
end
local replay_ok, replay_error = pcall(function()
	for _, key in ipairs(debug_spec.keys) do
		local lhs = key[1]:gsub("<leader>", vim.g.mapleader)
		vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(lhs, true, false, true), "xt", false)
		assert_owner(key[1], key[2])
	end
end)
for _, entry in ipairs(restore) do
	entry[1][entry[2]] = entry[3]
end
assert(replay_ok, replay_error)

local debug_keys = 0
for _, key in ipairs(debug_spec.keys) do
	assert(type(key[2]) == "function", "debug key must declare its callback: " .. key[1])
	assert_owner(key[1], key[2])
	debug_keys = debug_keys + 1
end
assert(debug_keys == 27, "update ownership coverage when changing Debug keys")

-- Negative controls: overwrites really do fail this assertion, including an
-- otherwise invisible buffer-local shadow. Restore the original global map.
local original = effective("<leader>db", contexts[1])
vim.keymap.set("n", "<leader>db", function() end)
local global_ok = pcall(assert_owner, "<leader>db", original.callback)
vim.keymap.set("n", "<leader>db", original.callback, { desc = original.desc, silent = original.silent == 1 })
assert(not global_ok, "ownership check missed a global overwrite")
vim.keymap.set("n", "<leader>db", function() end, { buffer = buf })
local buffer_ok = pcall(assert_owner, "<leader>db", original.callback)
vim.keymap.del("n", "<leader>db", { buffer = buf })
assert(not buffer_ok, "ownership check missed a buffer-local shadow")
assert_owner("<leader>db", original.callback)

-- The discover-all entry is defined outside the plugin spec. Exercise its
-- final callback with boundary spies, without opening a UI or triggering work.
local loader, wk = require("lz.n"), require("which-key")
local trigger_load, show = loader.trigger_load, wk.show
local function assert_discovery()
	for _, context in ipairs(contexts) do
		local calls = {}
		loader.trigger_load = function(name)
			calls[#calls + 1] = { "load", name }
		end
		wk.show = function(opts)
			calls[#calls + 1] = { "show", opts }
		end
		local ok, err = pcall(function()
			local mapping = effective("<leader>?", context)
			assert(type(mapping.callback) == "function", "missing discovery callback")
			mapping.callback()
			assert(
				vim.deep_equal(calls, { { "load", "which-key.nvim" }, { "show", { global = true } } }),
				"unexpected final which-key discovery action: " .. vim.inspect(calls)
			)
		end)
		loader.trigger_load, wk.show = trigger_load, show
		assert(ok, err)
	end
end
assert_discovery()
local discovery = effective("<leader>?", contexts[1])
vim.keymap.set("n", "<leader>?", function() end, { buffer = buf })
local discovery_ok = pcall(assert_discovery)
vim.keymap.del("n", "<leader>?", { buffer = buf })
assert(not discovery_ok, "discovery check missed an overwritten callback")
assert_discovery()
assert_owner("<leader>?", discovery.callback)

for _, group in ipairs({ "s", "g", "l", "d", "a", "t", "u", "f", "p", "r", "x", "m", "c" }) do
	for _, context in ipairs(contexts) do
		assert(
			vim.tbl_isempty(effective("<leader>" .. group, context)),
			"leader prefix is consumed before which-key: " .. group
		)
	end
end

-- The pinned which-key 3.17 health model records duplicate virtual mappings
-- while building its real view tree. Check the same tree it renders.
local mode_tree = require("which-key.buf").get({ mode = "n", buf = 0 })
assert(mode_tree and mode_tree.tree, "which-key did not build the normal-mode tree")
local debug_node = mode_tree.tree:find(" d")
assert(debug_node and debug_node:count() > 0)
vim.fn.setreg("a", "ciwvalue")
local macro_node = mode_tree.tree:find("@")
assert(macro_node and macro_node:can_expand(), "macro prefix needs its own discovery spec")
assert(macro_node:expand().a.desc == "Run macro a", "nonempty macro registers must be discoverable")
assert(macro_node:expand()["@"].desc == "Repeat last macro")
assert(macro_node:expand().a.keys == "@a", "macro selection must retain its parent prefix")
assert(macro_node:expand()["@"].keys == "@@", "repeat selection must replay the complete macro command")
vim.fn.setreg("a", "")
assert(not macro_node:expand().a, "empty macro registers must stay hidden")
assert(
	require("which-key.view").item(debug_node).desc == "Debug +" .. debug_node:count(),
	"collapsed groups must show their real child count"
)
assert(vim.tbl_contains(config.sort, "manual"), "common groups must retain explicit spec order")
assert(vim.tbl_isempty(require("which-key.tree").dups), "which-key found duplicate virtual mappings")
assert(
	#require("which-key.mappings").notifs == 0,
	"which-key reported mapping issues: " .. vim.inspect(require("which-key.mappings").notifs)
)

vim.api.nvim_buf_delete(buf, { force = true })
print(
	("Keymap discovery passed: %d described mappings, 16 groups, 27 Debug callback owners, discovery action, free leader prefixes, no virtual duplicates"):format(
		keymaps
	)
)
