-- Integration against the real pinned plugins, without model requests.
local load = require("lz.n").trigger_load
load({
	"claudecode.nvim",
	"sidekick.nvim",
	"codecompanion.nvim",
	"minuet-ai.nvim",
	"edgy.nvim",
	"smart-splits.nvim",
})
vim.wait(100)
assert(not vim.g.mayon_load_error, vim.g.mayon_load_error)
assert(require("mayon.generated").versions.codecompanion == "19.27.0", "CodeCompanion version drift")
assert(not package.loaded.copilot and not package.loaded["blink.cmp"])
local cc = require("codecompanion.config").config
assert(cc.interactions.chat.adapter == "deepseek" and cc.interactions.inline.adapter == "deepseek")
assert(cc.interactions.chat.keymaps.regenerate.modes.n == "<localleader>r", "chat regenerate shadows LSP gr prefixes")
for _, name in ipairs({ "codex", "claude_code" }) do
	local adapter = cc.adapters.acp[name]()
	local path = adapter.commands.default[1]
	assert(path:sub(1, 11) == "/nix/store/", "ACP adapter is not Nix-injected: " .. path)
	assert(vim.fn.executable(path) == 1, "missing ACP executable: " .. path)
	assert(not path:find("npx", 1, true))
end
assert(cc.extensions.history.enabled)
assert(require("codecompanion").version() == "19.27.0", "loaded CodeCompanion version drift")
local chat = require("codecompanion.interactions.chat").new({
	adapter = "deepseek",
	buffer_context = require("codecompanion.utils.context").get(),
	auto_submit = false,
	messages = {
		{ role = "user", content = "round13 local history fixture" },
		{ role = "llm", content = "round13 local fixture reply" },
	},
})
vim.wait(30) -- Let history process its scheduled ChatCreated hook before close.
chat.opts.save_id = "round13-local-fixture"
chat.opts.title = "round13 local fixture"
local history = require("codecompanion").extensions.history
history.save_chat(chat)
local saved = history.load_chat(chat.opts.save_id)
assert(
	saved and saved.adapter == "deepseek" and saved.title == chat.opts.title,
	"history save/load is incompatible with CodeCompanion 19.27"
)
assert(vim.iter(saved.messages):any(function(message)
	return type(message.content) == "string" and message.content:find("round13 local history fixture", 1, true) ~= nil
end))
chat:close()

-- CodeCompanion renders context metadata into its Markdown chat buffer. The
-- UI overlay may replace the visible rules label, but the source text and
-- context item must remain intact for the plugin's request pipeline.
local rules_chat = require("codecompanion").chat({ params = { adapter = "deepseek" } })
rules_chat:add_buf_message({ role = "user", content = "Review this change using the project rules." })
local context_ids = {
	"<file>src/app.lua</file>",
	"<rules>AGENTS.md</rules>",
	"<buf>main.lua</buf>",
	"<file>docs/guide.md</file>",
}
for index, id in ipairs(context_ids) do
	rules_chat.context:add({
		id = id,
		source = index == 2 and "rules" or "fixture",
		path = index == 2 and "AGENTS.md" or nil,
		opts = { visible = true },
	})
end
local rules_id = context_ids[2]
local rules_buf = rules_chat.bufnr
local rules_before = table.concat(vim.api.nvim_buf_get_lines(rules_buf, 0, -1, false), "\n")
for _, id in ipairs(context_ids) do
	assert(rules_before:find(id, 1, true), "CodeCompanion did not render mixed context fixture " .. id)
end
assert(#rules_chat.context_items == #context_ids and vim.iter(rules_chat.context_items):any(function(item)
	return item.id == rules_id and item.source == "rules" and item.path == "AGENTS.md"
end), "CodeCompanion mixed context metadata was not registered: " .. vim.inspect(rules_chat.context_items))
local panels = require("mayon.ui.ai_panels")
panels.decorate_chat(rules_buf)
local rows = vim.api.nvim_buf_get_lines(rules_buf, 0, -1, false)
local rules_after = table.concat(rows, "\n")
assert(rules_after == rules_before, "rules rendering must be visual-only and leave the chat protocol buffer unchanged")
local rules_namespace = vim.api.nvim_create_namespace("MayonAIPanels")
local rule_row, context_row
for row, line in ipairs(rows) do
	if line:find(rules_id, 1, true) then
		rule_row = row - 1
	elseif line:match("^%s*>%s*Context:%s*$") then
		context_row = row - 1
	end
end
assert(rule_row and context_row, "mixed CodeCompanion fixture must include its Context heading and rules row")
local rule_overlay
local concealed_rows = {}
for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(rules_buf, rules_namespace, 0, -1, { details = true })) do
	local details = mark[4]
	if details.conceal ~= nil then
		concealed_rows[mark[2]] = true
		if details.virt_text then
			rule_overlay = details
		end
	end
end
assert(rule_overlay, "the raw rules block needs a visible inline replacement")
assert(concealed_rows[rule_row], "the AGENTS reference row was not concealed")
assert(not concealed_rows[context_row], "the Context heading must remain visible for mixed context items")
for _, id in ipairs({ context_ids[1], context_ids[3], context_ids[4] }) do
	local row
	for index, line in ipairs(rows) do
		if line:find(id, 1, true) then
			row = index - 1
			break
		end
	end
	assert(row and not concealed_rows[row], "a non-rules context item was concealed: " .. id)
end
assert(
	rule_overlay.virt_text_pos == "overlay" and rule_overlay.virt_text[1][1] == "· 已加载规则：AGENTS.md",
	"the replacement should be a concise muted loaded-rules label"
)
local outbound = {
	content = "## YOU\n\n> Context:\n\n> - " .. table.concat(context_ids, "\n> - ") .. "\n\nReview the change.",
}
rules_chat.context:remove(outbound)
for _, id in ipairs(context_ids) do
	assert(not outbound.content:find(id, 1, true), "context reference duplicated into the user prompt: " .. id)
end
assert(#rules_chat.context_items == #context_ids and vim.iter(rules_chat.context_items):any(function(item)
	return item.id == rules_id and item.source == "rules" and item.path == "AGENTS.md"
end), "removing rendered references must preserve CodeCompanion context metadata")

-- Without a Context heading, attach the summary to the rule row only.
local bare_buf = vim.api.nvim_create_buf(false, true)
vim.bo[bare_buf].filetype = "codecompanion"
local bare_lines = {
	"## YOU",
	"",
	"> - <file>src/previous.lua</file>",
	"> - <rules>nested/AGENTS.md</rules>",
	"> - <file>src/next.lua</file>",
	"",
	"Review this change.",
}
vim.api.nvim_buf_set_lines(bare_buf, 0, -1, false, bare_lines)
panels.decorate_chat(bare_buf)
assert(
	vim.deep_equal(vim.api.nvim_buf_get_lines(bare_buf, 0, -1, false), bare_lines),
	"a headerless rules row must keep all source lines intact"
)
local rule_row, previous_row, next_row = 3, 2, 4
local bare_overlay
local bare_concealed = {}
for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(bare_buf, rules_namespace, 0, -1, { details = true })) do
	local details = mark[4]
	if details.conceal ~= nil then
		bare_concealed[mark[2]] = true
		if details.virt_text then
			bare_overlay = details
		end
	end
end
assert(bare_concealed[rule_row], "headerless rules reference was not concealed")
assert(
	not bare_concealed[previous_row] and not bare_concealed[next_row],
	"headerless context concealed neighboring files"
)
assert(
	bare_overlay
		and bare_overlay.virt_text_pos == "overlay"
		and bare_overlay.virt_text[1][1] == "· 已加载规则：AGENTS.md",
	"headerless rules should receive a summary on the reference row"
)
-- Leave the synthetic chat open until the test process exits. The history
-- extension resolves ChatClosed asynchronously and expects registered chats.

assert(require("sidekick.config").cli.tools.claude == nil, "Claude must have one terminal owner")
assert(require("sidekick.config").cli.tools.codex and require("sidekick.config").cli.tools.grok)
local mini_diff = require("mini.diff")
assert(
	mini_diff.config.view.style == "number",
	"MiniDiff must keep its CC inline review markers out of the sign gutter"
)
assert(mini_diff.config.source.name == "manual", "MiniDiff must not attach as a Git change owner")
local completion = require("mayon.features.ai_completion")
local existing = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(existing)
assert(completion.set("deepseek") == "deepseek" and vim.g.sidekick_nes == false)
assert(vim.b[existing].minuet_virtual_text_auto_trigger, "existing buffer missed DeepSeek auto trigger")
local delivered = 0
local pending_response = completion.guard(function()
	delivered = delivered + 1
end)
pending_response({ "current" })
assert(delivered == 1)
completion.set("off")
pending_response({ "stale" })
assert(delivered == 1, "late DeepSeek response survived provider switch")
-- The same backend wrapper used in production, with a deferred local transport.
completion.set("deepseek")
local original_key = vim.env.DEEPSEEK_API_KEY
vim.env.DEEPSEEK_API_KEY = "local-fixture-unused-by-transport"
local transport_callback
local wrapped = completion.wrap_backend(function(_, callback)
	transport_callback = callback
end)
wrapped({}, function()
	delivered = delivered + 1
end)
transport_callback({ "first" })
assert(delivered == 2)
completion.set("off")
transport_callback({ "late-second" })
assert(delivered == 2, "backend wiring bypassed provider guard")
vim.env.DEEPSEEK_API_KEY = original_key
vim.api.nvim_exec_autocmds("User", { pattern = "MinuetRequestStartedPre", data = { n_requests = 2 } })
vim.api.nvim_exec_autocmds("User", { pattern = "MinuetRequestFinished" })
assert(completion.pending == 1, "parallel FIM request cleared busy state early")
vim.api.nvim_exec_autocmds("User", { pattern = "MinuetRequestFinished" })
assert(completion.pending == 0)
completion.busy = true
assert(completion.set("off") == "off" and not completion.accept() and not completion.busy)
assert(completion.set("copilot") == "copilot" and vim.g.sidekick_nes == true)
assert(not pcall(completion.set, "invalid"))
completion.set("off")
assert(require("minuet").config.provider == "openai_fim_compatible")
assert(require("minuet").config.provider_options.openai_fim_compatible.api_key == "DEEPSEEK_API_KEY")
for _, key in ipairs({
	" ac",
	" as",
	" aA",
	" aD",
	" ax",
	" ag",
	" ad",
	" ai",
	" af",
	" ae",
	" at",
	" am",
	" ap",
	" au",
}) do
	local mode = (key == " as" or key == " at") and "x" or "n"
	assert(vim.fn.maparg(key, mode) ~= "", "missing AI key: " .. key)
end
-- Provider commands remain available offline and explain missing credentials
-- without opening an interaction or making a network request.
local key_before = vim.env.DEEPSEEK_API_KEY
vim.env.DEEPSEEK_API_KEY = ""
local notices = {}
local notify = vim.notify
vim.notify = function(message)
	notices[#notices + 1] = tostring(message)
end
local chat_key = vim.fn.maparg(" ad", "n", false, true)
assert(
	type(chat_key.callback) == "function" and chat_key.desc == "Open DeepSeek Chat",
	"DeepSeek mapping is not the guarded action"
)
local missing_key = require("mayon.features.ai_completion").require_deepseek_key()
vim.notify = notify
vim.env.DEEPSEEK_API_KEY = key_before
assert(not missing_key and #notices == 1 and notices[1]:find("DEEPSEEK_API_KEY", 1, true))
for _, key in ipairs({ "<C-h>", "<C-j>", "<C-k>", "<C-l>", "<M-h>", "<M-j>", "<M-k>", "<M-l>" }) do
	assert(vim.fn.maparg(key, "n") ~= "", "missing smart split key: " .. key)
end
-- Real mini.diff bridge: edits remain unsaved, reject restores the buffer;
-- accepting keeps editable content and restores any pre-existing local maps.
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
vim.bo.filetype = "lua"
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "return 1" })
local accepted, rejected = 0, 0
local args = {
	bufnr = buf,
	ft = "lua",
	inline = true,
	diff_id = 7,
	from_lines = { "return 1" },
	to_lines = { "return 2" },
	keymaps = {
		on_accept = function()
			accepted = accepted + 1
		end,
		on_reject = function()
			rejected = rejected + 1
		end,
	},
}
local helpers = require("codecompanion.helpers")
helpers.show_diff(args)
assert(vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1] == "return 2")
assert(not pcall(helpers.show_diff, args), "overlapping inline review was allowed")
vim.fn.maparg(",r", "n", false, true).callback()
assert(rejected == 1 and vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1] == "return 1")
helpers.show_diff(args)
vim.fn.maparg(",a", "n", false, true).callback()
assert(accepted == 1 and vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1] == "return 2")
assert(vim.bo.modified and not vim.b.mayon_inline_review)
vim.bo.modified = false
-- Real native Claude diff: accept/reject via its public commands, no CLI.
local path = vim.fn.tempname() .. ".lua"
vim.fn.writefile({ "return 1" }, path)
vim.cmd.edit(path)
local diff = require("claudecode.diff")
local function review(title, decision)
	local resolved
	diff._setup_blocking_diff(
		{ old_file_path = path, new_file_path = path, new_file_contents = "return 3\n", tab_name = title },
		function(result)
			resolved = result
		end
	)
	vim.wait(50)
	assert(vim.b.claudecode_diff_tab_name == title)
	assert(vim.wo.winhighlight:find("DiffChange:DiffAdd", 1, true), "Claude proposed lines must use a green background")
	local target = vim.b.claudecode_diff_target_win
	assert(
		target and vim.wo[target].winhighlight:find("DiffChange:DiffDelete", 1, true),
		"Claude original lines must use a red background"
	)
	local proposed = vim.api.nvim_get_current_win()
	local original_style = vim.w[proposed].mayon_claude_style
	vim.cmd("diffoff")
	-- -c tests run before VimEnter, when Neovim suppresses OptionSet.
	if vim.v.vim_did_enter == 0 then
		vim.api.nvim_exec_autocmds("OptionSet", { pattern = "diff" })
	end
	vim.wait(30)
	assert(not vim.w[proposed].mayon_claude_style, "diffoff must restore a retained review window")
	assert(vim.wo.winhighlight == original_style.winhighlight, "diffoff left red/green mappings in a normal window")
	vim.api.nvim_set_current_win(target)
	assert(not vim.wo.cursorline, "entering the original diff window overlaid its review colors")
	vim.api.nvim_set_current_win(proposed)
	vim.wait(30)
	assert(not vim.w[proposed].mayon_claude_style, "re-entering a non-diff review window reapplied diff styles")
	vim.cmd("diffthis")
	if vim.v.vim_did_enter == 0 then
		vim.api.nvim_exec_autocmds("OptionSet", { pattern = "diff" })
	end
	vim.wait(30)
	assert(vim.wo.winhighlight:find("DiffChange:DiffAdd", 1, true), "diffthis must restore the review palette")
	assert(vim.fn.maparg(",a", "n") ~= "" and vim.fn.maparg(",r", "n") ~= "")
	assert(
		vim.api.nvim_eval_statusline(vim.wo.winbar, { winid = 0 }).str:find(",a 接受", 1, true),
		"diff lacks its review hint"
	)
	vim.cmd(decision)
	assert(resolved, "Claude diff did not resolve")
	diff.close_diff_by_tab_name(title)
	vim.wait(20)
	if vim.api.nvim_win_is_valid(target) then
		assert(not vim.w[target].mayon_claude_style, "closing Claude review must restore the original window style")
	end
	return resolved
end
review("fixture-deny", "ClaudeCodeDiffDeny")
assert(vim.fn.readfile(path)[1] == "return 1", "reject wrote Claude changes")
local response = review("fixture-accept", "ClaudeCodeDiffAccept")
assert(
	response.content[1].text == "FILE_SAVED" and response.content[2].text == "return 3\n",
	"accept did not return edited content to Claude"
)
-- The protocol returns content to the CLI; the CLI writes the target file.
assert(vim.fn.readfile(path)[1] == "return 1", "protocol test unexpectedly wrote the source file")
vim.fn.delete(path)
require("claudecode").stop()
-- Runtime API scan: unique mappings per mode and no leaf-prefix conflict in
-- our leader namespace (the API exposes only final effective mappings).
for _, mode in ipairs({ "n", "x", "i", "t" }) do
	local seen, leader = {}, {}
	for _, mapping in ipairs(vim.api.nvim_get_keymap(mode)) do
		assert(not seen[mapping.lhs], "duplicate mapping: " .. mode .. ":" .. mapping.lhs)
		seen[mapping.lhs] = true
		if mapping.lhs:sub(1, 1) == " " then
			leader[#leader + 1] = mapping.lhs
		end
	end
	table.sort(leader)
	for i = 1, #leader - 1 do
		assert(leader[i + 1]:sub(1, #leader[i]) ~= leader[i], "leader leaf-prefix conflict: " .. leader[i])
	end
	print("keymaps " .. mode .. ": " .. vim.tbl_count(seen) .. ", duplicate/prefix conflicts=0")
end
assert(vim.v.errmsg == "", vim.v.errmsg)
print("AI adapters, provider switching, inline and Claude accept/reject, layouts and keys passed")
