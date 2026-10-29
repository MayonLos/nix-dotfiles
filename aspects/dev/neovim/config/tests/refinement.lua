-- Offline integration checks for the refined floating surfaces, discoverable
-- mappings, LSP buffer maps, and native Copilot snippet acceptance.
vim.api.nvim_exec_autocmds("User", { pattern = "MayonVeryLazy" })
local ai_completion = require("mayon.features.ai_completion")
ai_completion.set("off")
ai_completion.copilot_setup()
assert(not vim.lsp.is_enabled("copilot"), "off before lazy setup must not start Copilot")
ai_completion.set("copilot")
assert(vim.lsp.is_enabled("copilot"), "Copilot must be enabled when explicitly selected")
ai_completion.set("off")
assert(not vim.lsp.is_enabled("copilot"), "off must stop the inactive Copilot client")

local palette = require("mayon.generated").palette
local theme = require("mayon.ui.theme")
theme.refresh()

local function highlight(name)
	return vim.api.nvim_get_hl(0, { name = name, link = false })
end

local function color(value)
	return tonumber(value:sub(2), 16)
end

local function assert_single_surface(win, label)
	local config = vim.api.nvim_win_get_config(win)
	assert(config.relative ~= "", label .. " must be a real floating window")
	local single = config.border == nil and vim.o.winborder == "single"
		or type(config.border) == "table" and config.border[1] == "┌"
	assert(
		single,
		label .. " must use a single-line border: " .. vim.inspect(config.border) .. " / " .. vim.o.winborder
	)
	return config
end

local border = highlight("FloatBorder")
local title = highlight("FloatTitle")
assert(border.fg == color(require("mayon.ui.theme").float_edge()), "global float border must use the quiet edge")
assert(border.bg == color(palette.bg), "global float border must share the editor surface")
assert(title.fg == color(palette.muted) and title.bg == color(palette.bg), "global float title palette mismatch")
local popup_border = highlight("MayonPopupBorder")
local popup_title = highlight("MayonPopupTitle")
assert(popup_border.fg == border.fg and popup_border.bg == border.bg, "input border must match FloatBorder")
assert(popup_title.fg == title.fg and popup_title.bg == title.bg, "input title must match FloatTitle")

-- Open Snacks' actual input prompt and inspect the resulting window options.
local before_input = {}
for _, win in ipairs(vim.api.nvim_list_wins()) do
	before_input[win] = true
end
local input_result
vim.ui.input({ prompt = "Fixture prompt: ", title = " Input fixture " }, function(value)
	input_result = value
end)
local input_win
assert(
	vim.wait(1500, function()
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			if not before_input[win] and vim.api.nvim_win_get_config(win).relative ~= "" then
				input_win = win
				return true
			end
		end
		return false
	end, 10),
	"Snacks input did not create a floating prompt"
)
local input_config = assert_single_surface(input_win, "Snacks input")
assert(type(input_config.title) == "table", "input should render its native title chunks")
assert(
	vim.wo[input_win].winhighlight:find("FloatBorder:SnacksInputBorder", 1, true),
	"input window must use the shared popup border group"
)
local input_border = highlight("SnacksInputBorder")
assert(input_border.fg == border.fg and input_border.bg == border.bg, "rendered input border color diverged")
vim.api.nvim_win_close(input_win, true)

-- Notifications run through the configured renderer, not a copied config table.
local notification_marker = "refinement-notification-fixture"
vim.notify(notification_marker, vim.log.levels.INFO, { title = "Notification fixture", timeout = 30000 })
local notification_win
assert(
	vim.wait(1500, function()
		for _, win in ipairs(vim.api.nvim_list_wins()) do
			local config = vim.api.nvim_win_get_config(win)
			if config.relative ~= "" then
				local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)
				if table.concat(lines, "\n"):find(notification_marker, 1, true) then
					notification_win = win
					return true
				end
			end
		end
		return false
	end, 10),
	"configured notifier did not render a notification window"
)
local notification_config = assert_single_surface(notification_win, "notification")
assert(type(notification_config.title) == "table", "notification should render title chunks")
assert(
	vim.wo[notification_win].winhighlight:find("FloatBorder:FloatBorder", 1, true)
		and vim.wo[notification_win].winhighlight:find("FloatTitle:FloatTitle", 1, true),
	"notification must use the shared border and title groups"
)
vim.api.nvim_win_close(notification_win, true)

-- Load AI integration and create its local fixture chat; no provider call is made.
vim.env.DEEPSEEK_API_KEY = nil
vim.env.OPENAI_API_KEY = nil
require("lz.n").trigger_load("codecompanion.nvim")
local panels = require("mayon.ui.ai_panels")
panels.setup()
vim.o.columns = 102 -- formerly claimed by Edgy despite the AI float threshold of 120
local chat_buf = panels.open_fixture("chat")
vim.wait(100)
local chat_win = vim.fn.win_findbuf(chat_buf)[1]
assert(chat_win, "offline AI fixture must open its chat window")
local chat_config = assert_single_surface(chat_win, "AI chat")
assert(type(chat_config.title) == "table", "AI chat should render title chunks")
border = highlight("FloatBorder")
title = highlight("FloatTitle")
assert(border.fg == color(require("mayon.ui.theme").float_edge()) and border.bg == color(palette.bg))
assert(title.fg == color(palette.muted) and title.bg == color(palette.bg), "AI loading changed FloatTitle")
assert(highlight("CodeCompanionVirtualText").fg == color(palette.muted), "AI hints should remain muted")
local ai_border_group = vim.wo[chat_win].winhighlight:match("FloatBorder:([^,]+)") or "FloatBorder"
local ai_border = highlight(ai_border_group)
assert(ai_border.fg == border.fg and ai_border.bg == border.bg, "AI float border mapping diverged from FloatBorder")
vim.api.nvim_buf_delete(chat_buf, { force = true })

-- New commands and the f/s/r/d groups must be discoverable without a mapping
-- consuming the prefix itself.
local function mapping(lhs, mode)
	return vim.fn.maparg(lhs, mode or "n", false, true)
end

for lhs, description in pairs({
	["<leader>ff"] = "Find Files",
	["<leader>sn"] = "Show Notifications",
	["<leader>rs"] = "Open Serial Terminal",
}) do
	local entry = mapping(lhs)
	assert(type(entry.callback) == "function" and entry.desc == description, "missing described mapping: " .. lhs)
end
for _, prefix in ipairs({ "<leader>f", "<leader>s", "<leader>r", "<leader>d" }) do
	assert(mapping(prefix).lhs == nil, "which-key prefix is unexpectedly consumed: " .. prefix)
end
local which_key = require("mayon.ui.whichkey").config()
local groups = {}
for _, spec in ipairs(which_key.spec) do
	if spec.group then
		groups[spec[1]] = spec.group
	end
end
for prefix, label in pairs({
	["<leader>f"] = "Files",
	["<leader>s"] = "Search",
	["<leader>r"] = "Run",
	["<leader>d"] = "Debug",
}) do
	assert(groups[prefix] == label, "which-key group missing for " .. prefix)
end

-- Load DAP lazily against the real tools dev package and verify its public
-- commands and discoverable descriptions.
require("lz.n").trigger_load("nvim-dap")
assert(
	package.loaded["dap-view"] and package.loaded["nvim-dap-virtual-text"],
	"DAP UI plugins did not load from the dev closure"
)
local commands = vim.api.nvim_get_commands({})
assert(commands.DapContinue and commands.DapToggleBreakpoint, "nvim-dap public commands did not load")
for lhs, description in pairs({
	["<leader>dc"] = "Continue debugging",
	["<leader>db"] = "Toggle breakpoint",
	["<leader>dn"] = "Step over",
	["<leader>dq"] = "Disconnect debugger",
}) do
	local entry = mapping(lhs)
	assert(type(entry.callback) == "function" and entry.desc == description, "missing DAP mapping: " .. lhs)
end
assert(mapping("<leader>d").lhs == nil, "DAP group prefix must remain available to which-key")

-- Simulate LspAttach on a fixture buffer, then inspect the buffer-local maps.
vim.cmd.packadd("nvim-lspconfig")
require("mayon.lsp").setup()
local buffer = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buffer)
vim.bo[buffer].filetype = "c"
local get_client_by_id = vim.lsp.get_client_by_id
vim.lsp.get_client_by_id = function(id)
	if id == -1 then
		return {
			id = id,
			name = "fixture",
			server_capabilities = {},
			supports_method = function()
				return false
			end,
		}
	end
	return get_client_by_id(id)
end
vim.api.nvim_exec_autocmds("LspAttach", { buffer = buffer, data = { client_id = -1 } })
vim.lsp.get_client_by_id = get_client_by_id
local local_maps = {}
for _, entry in ipairs(vim.api.nvim_buf_get_keymap(buffer, "n")) do
	local_maps[entry.lhs] = entry
end
assert(local_maps.grr and local_maps.grr.desc == "Find References Preview", "LspAttach should install described grr")
assert(local_maps.gK and local_maps.gK.desc == "Show Signature Help", "LspAttach should install described gK")
assert(not local_maps.gr, "LspAttach must not consume the gr prefix")

-- Accept one word from a local Copilot-shaped snippet fixture. Stub only the
-- native completion request, so the real 0.12 snippet grammar transforms it.
local ai_completion = require("mayon.features.ai_completion")
local inline = vim.lsp.inline_completion
local old_get = inline.get
local old_provider = ai_completion.provider
local accepted
ai_completion.provider = "copilot"
inline.get = function(options)
	accepted =
		options.on_accept({ insert_text = { value = "emit(${1:argument})$0" }, command = { command = "fixture" } })
	return true
end
assert(ai_completion.accept_word(), "local Copilot completion fixture should accept a word")
inline.get = old_get
ai_completion.provider = old_provider
assert(accepted and accepted.insert_text == "emit", "native snippet grammar must yield the first accepted word")
assert(accepted.command == nil, "partial word acceptance must not run a whole-suggestion command")
local parsed_snippet = tostring(require("vim.lsp._snippet_grammar").parse("emit(${1:argument})$0"))
assert(parsed_snippet == "emit(argument)", "Neovim native snippet grammar API changed unexpectedly")

print("Refinement float surfaces, mappings, LSP attach, DAP discoverability, and offline Copilot acceptance passed")
