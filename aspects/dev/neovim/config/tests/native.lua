local runtime = vim.env.VIMRUNTIME
assert(runtime:find("neovim%-unwrapped%-0%.12%.6"), "native feature checks target the locked Neovim 0.12.6 runtime")
assert(package.loaded["vim._core.ui2"], "bootstrap should enable native ui2")
assert(type(vim.ui.progress_status) == "function")
assert(type(vim.lsp.codelens.enable) == "function")
assert(type(vim.lsp.linked_editing_range.enable) == "function")
assert(type(vim.lsp.on_type_formatting.enable) == "function")
assert(type(vim.lsp.document_color.enable) == "function")
assert(type(vim.lsp.buf.workspace_diagnostics) == "function")
assert(type(vim.treesitter.select) == "function")

local global_maps = {}
for _, keymap in ipairs(vim.api.nvim_get_keymap("n")) do
	if keymap.desc then
		global_maps[keymap.desc] = true
	end
end
for _, desc in ipairs({
	"Show Undo History",
	"Restart Neovim",
	"Collect Project Diagnostics",
	"Toggle Code Lens",
}) do
	assert(global_maps[desc], "missing native feature mapping: " .. desc)
end

-- Exercise LspAttach capability gating without launching a language server.
local lsp = vim.lsp
local buf = vim.api.nvim_get_current_buf()
local originals = {
	get_client = lsp.get_client_by_id,
	codelens = lsp.codelens.enable,
	linked = lsp.linked_editing_range.enable,
	on_type = lsp.on_type_formatting.enable,
	color = lsp.document_color.enable,
	completion = require("mayon.features.native_completion").attach,
}
local calls = {}
lsp.get_client_by_id = function(id)
	if id == -2 then
		return {
			id = id,
			supports_method = function(_, method)
				return method ~= "textDocument/unsupported"
			end,
		}
	end
	return originals.get_client(id)
end
lsp.codelens.enable = function(enable, filter)
	calls.codelens = { enable, filter }
end
lsp.linked_editing_range.enable = function(enable, filter)
	calls.linked = { enable, filter }
end
lsp.on_type_formatting.enable = function(enable, filter)
	calls.on_type = { enable, filter }
end
lsp.document_color.enable = function(enable, filter)
	calls.color = { enable, filter }
end
require("mayon.features.native_completion").attach = function(client, bufnr)
	calls.completion = { client.id, bufnr }
end
vim.api.nvim_exec_autocmds("LspAttach", { group = "NativeLspAttach", buffer = buf, data = { client_id = -2 } })
assert(calls.codelens and calls.codelens[1] == false and calls.codelens[2].client_id == -2)
assert(calls.linked and calls.linked[1] and calls.linked[2].client_id == -2)
assert(calls.on_type and calls.on_type[1] and calls.on_type[2].client_id == -2)
assert(calls.color and calls.color[1] and calls.color[2].bufnr == buf)
assert(calls.completion and calls.completion[1] == -2 and calls.completion[2] == buf)
assert(#vim.api.nvim_get_autocmds({ group = "MayonSignatureHelp" .. buf, event = "InsertCharPre" }) > 0)
lsp.get_client_by_id = originals.get_client
lsp.codelens.enable = originals.codelens
lsp.linked_editing_range.enable = originals.linked
lsp.on_type_formatting.enable = originals.on_type
lsp.document_color.enable = originals.color
require("mayon.features.native_completion").attach = originals.completion

-- Initialize the LSP bridge when this test runs outside the startup path.
local has_progress_bridge, progress_bridge = pcall(vim.api.nvim_get_autocmds, { group = "NativeLspProgressBridge" })
if not has_progress_bridge or #progress_bridge == 0 then
	vim.cmd.packadd("nvim-lspconfig")
	local completion = require("mayon.features.ai_completion")
	local copilot_setup = completion.copilot_setup
	completion.copilot_setup = function() end
	require("mayon.lsp").setup()
	completion.copilot_setup = copilot_setup
end

vim.ui.progress_status() -- initializes Neovim's native Progress event collector.
assert(vim.tbl_contains(vim.opt.messagesopt:get(), "progress:"), "progress must stay out of the message area")
local message_ns = vim.api.nvim_create_namespace("NativeProgressMessagesTest")
local messages = {}
vim.ui_attach(message_ns, { ext_messages = true }, function(event, kind, chunks)
	if event == "msg_show" then
		messages[#messages + 1] = { kind = kind, chunks = chunks }
	end
	return true
end)
vim.api.nvim_echo({ { "message observer ready" } }, false, {})
assert(#messages > 0, "message observer must see ordinary messages")
messages = {}
local bridge_client_id = 8122
local bridge_client = {
	id = bridge_client_id,
	name = "bridge-test",
	attached_buffers = { [buf] = true },
}
local get_client_by_id = vim.lsp.get_client_by_id
vim.lsp.get_client_by_id = function(id)
	if id == bridge_client_id then
		return bridge_client
	end
	return get_client_by_id(id)
end
local bridged_events = {}
vim.api.nvim_create_autocmd("Progress", {
	group = vim.api.nvim_create_augroup("NativeLspProgressTest", { clear = true }),
	pattern = "lsp",
	callback = function(event)
		bridged_events[#bridged_events + 1] = event.data
	end,
})
local function lsp_progress(token, kind, percentage, message)
	vim.api.nvim_exec_autocmds("LspProgress", {
		data = {
			client_id = bridge_client_id,
			params = {
				token = token,
				value = { kind = kind, title = "Bridge test", percentage = percentage, message = message },
			},
		},
	})
end
lsp_progress("work", "begin", 0, "Starting")
assert(vim.ui.progress_status():find("(1)", 1, true), "LspProgress begin should enter native Progress status")
lsp_progress("work", "report", 55, "Loading workspace: 55% 138/249")
assert(vim.ui.progress_status():find("55", 1, true), "LspProgress report should update native progress")
assert(bridged_events[#bridged_events].source == "lsp" and bridged_events[#bridged_events].status == "running")
-- Evaluate the complete Heirline output, not just the progress provider string.
local get_clients = vim.lsp.get_clients
vim.lsp.get_clients = function()
	return { bridge_client }
end
local columns = vim.o.columns
for _, width in ipairs({ 80, 120, 180 }) do
	vim.o.columns = width
	local rail = vim.api.nvim_eval_statusline(vim.o.statusline, { maxwidth = width }).str
	assert(rail:find("55%(1)", 1, true), "progress lost its single percent: " .. rail)
	assert(not rail:find("55%%", 1, true), "progress was escaped twice: " .. rail)
end
vim.o.columns = columns
vim.lsp.get_clients = get_clients
lsp_progress("work", "end", 100, "Finished")
assert(vim.ui.progress_status() == "", "LspProgress end should clear native progress")
assert(bridged_events[#bridged_events].status == "success")
vim.cmd.redraw()
vim.wait(20)
vim.ui_detach(message_ns)
assert(#messages == 0, "LSP progress leaked into the message area: " .. vim.inspect(messages))

lsp_progress("stale", "begin", 0, "Will detach")
bridge_client.attached_buffers = {}
vim.api.nvim_exec_autocmds("LspDetach", { buffer = buf, data = { client_id = bridge_client_id } })
assert(
	vim.wait(1000, function()
		return vim.ui.progress_status() == ""
	end, 10),
	"detaching last LSP should clear native progress: " .. vim.ui.progress_status() .. vim.inspect(bridged_events)
)
assert(bridged_events[#bridged_events].status == "cancel")
vim.lsp.get_client_by_id = get_client_by_id

vim.api.nvim_exec_autocmds("Progress", {
	data = { id = 8123, title = "Native LSP task", percent = 40, status = "running" },
})
local progress_status = vim.ui.progress_status()
assert(
	progress_status:find("40", 1, true) and progress_status:find("(1)", 1, true),
	"native statusline should summarize running progress"
)
vim.api.nvim_exec_autocmds("Progress", {
	data = { id = 8123, title = "Native LSP task", percent = 100, status = "success" },
})
assert(vim.ui.progress_status() == "", "finished native progress should clear from statusline")
print("native Neovim UI/LSP checks passed")

vim.cmd.packadd("nvim.undotree")
vim.cmd.packadd("nvim.difftool")
assert(vim.fn.exists(":Undotree") == 2 and vim.fn.exists(":DiffTool") == 2)
assert(vim.fn.exists(":restart") == 2)
assert(vim.tbl_contains(vim.opt.diffopt:get(), "inline:word"))
assert(vim.o.pumborder == "none" and vim.o.pumheight <= 10)
local muted = tonumber(require("mayon.generated").palette.muted:sub(2), 16)
for _, name in ipairs({ "ComplHint", "ComplHintMore", "MinuetVirtualText" }) do
	assert(vim.api.nvim_get_hl(0, { name = name, link = false }).fg == muted)
end
