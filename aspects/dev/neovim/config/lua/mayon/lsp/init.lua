local M = {}
local util = require("mayon.util")

-- Native ui.progress_status only collects Progress events; LSP emits LspProgress.
-- Bridge once, keep a flat table of live tokens for LspDetach cleanup.
local active_progress = {}

local function progress_id(client_id, token)
	return ("lsp:%s:%s:%s"):format(client_id, type(token), tostring(token))
end

local function publish_progress(id, client_id, value, status)
	local client = vim.lsp.get_client_by_id(client_id)
	local title = value.title or (client and client.name) or "LSP"
	local text = value.message or title
	local percent =
		math.max(0, math.min(100, math.floor(tonumber(value.percentage) or (status == "success" and 100 or 0))))
	if status == "running" then
		active_progress[id] = client_id
	else
		active_progress[id] = nil
	end
	vim.api.nvim_exec_autocmds("Progress", {
		pattern = "lsp",
		data = {
			id = id,
			title = tostring(title),
			text = tostring(text),
			source = "lsp",
			status = status,
			percent = percent,
			data = { client_id = client_id },
		},
	})
end

local function progress()
	vim.ui.progress_status() -- Also initialize when --clean callers skip the statusline.
	local group = vim.api.nvim_create_augroup("NativeLspProgressBridge", { clear = true })
	vim.api.nvim_create_autocmd("LspProgress", {
		group = group,
		callback = function(event)
			local data = event.data or {}
			local client_id = data.client_id
			local params = data.params or {}
			local value = params.value
			local token = params.token
			if client_id == nil or token == nil or type(value) ~= "table" then
				return
			end
			local status = (value.kind == "begin" or value.kind == "report") and "running"
				or value.kind == "end" and "success"
			if not status then
				return
			end
			publish_progress(progress_id(client_id, token), client_id, value, status)
		end,
	})
	vim.api.nvim_create_autocmd("LspDetach", {
		group = group,
		callback = function(event)
			local client_id = (event.data or {}).client_id
			if client_id == nil then
				return
			end
			vim.schedule(function()
				local client = vim.lsp.get_client_by_id(client_id)
				if client and next(client.attached_buffers or {}) then
					return
				end
				for id, owner in pairs(active_progress) do
					if owner == client_id then
						publish_progress(id, client_id, { message = "" }, "cancel")
					end
				end
			end)
		end,
	})
end

local function map(bufnr, lhs, rhs, desc)
	vim.keymap.set("n", lhs, rhs, { buffer = bufnr, desc = desc, silent = true })
end

local function source_header()
	local client = vim.lsp.get_clients({ bufnr = 0, name = "clangd" })[1]
	if not client then
		vim.notify("clangd not attached", vim.log.levels.WARN)
		return
	end
	local params = vim.lsp.util.make_text_document_params(0)
	client:request("textDocument/switchSourceHeader", params, function(err, result)
		if err or not result then
			vim.notify("clangd: no matching source/header", vim.log.levels.WARN)
			return
		end
		vim.cmd.edit(vim.fn.fnameescape(vim.uri_to_fname(result)))
	end, 0)
end

local function signature()
	local opts = require("mayon.ui.floats").options("signature", { border = util.border })
	vim.lsp.buf.signature_help(opts)
end

local function attach(event)
	local bufnr = event.buf
	local client = vim.lsp.get_client_by_id(event.data and event.data.client_id)
	if not client then
		return
	end
	map(bufnr, "gd", vim.lsp.buf.definition, "Jump to Definition")
	map(bufnr, "grr", function()
		Snacks.picker.lsp_references()
	end, "Find References Preview")
	map(bufnr, "gK", signature, "Show Signature Help")
	map(bufnr, "gD", vim.lsp.buf.declaration, "Jump to Declaration")
	map(bufnr, "grt", vim.lsp.buf.type_definition, "Jump to Type Definition")
	map(bufnr, "gi", vim.lsp.buf.implementation, "Jump to Implementation")
	map(bufnr, "K", function()
		local opts = require("mayon.ui.floats").options("hover", { border = util.border })
		vim.lsp.buf.hover(opts)
	end, "Show Hover Documentation")
	map(bufnr, "grx", vim.lsp.codelens.run, "Run Code Lens")
	local function supports(method)
		return client:supports_method(method, bufnr)
	end
	if supports("textDocument/codeLens") then
		vim.lsp.codelens.enable(false, { bufnr = bufnr, client_id = client.id })
	end
	if supports("textDocument/linkedEditingRange") then
		vim.lsp.linked_editing_range.enable(true, { client_id = client.id })
	end
	if supports("textDocument/onTypeFormatting") then
		vim.lsp.on_type_formatting.enable(true, { client_id = client.id })
	end
	if supports("textDocument/documentColor") then
		vim.lsp.document_color.enable(true, { bufnr = bufnr, client_id = client.id })
	end
	if supports("textDocument/completion") then
		require("mayon.features.native_completion").attach(client, bufnr)
	end
end

local function restart()
	-- Native `:lsp restart` without names restarts only the clients attached to
	-- the current buffer and re-attaches their buffers; no FileType re-trigger.
	if #vim.lsp.get_clients({ bufnr = 0 }) > 0 then
		vim.cmd("lsp restart")
	end
end

local function diagnostics()
	require("mayon.ui.icons").diagnostics()
	vim.diagnostic.config({
		virtual_text = false,
		virtual_lines = false,
		severity_sort = true,
		float = {
			border = util.border,
			source = "if_many",
			header = "",
			title = " diagnostics ",
			title_pos = "center",
		},
	})
	vim.keymap.set("n", "<leader>ll", function()
		local all = vim.diagnostic.config().virtual_lines == true
		vim.diagnostic.config({ virtual_lines = all and { current_line = true } or true })
	end, { desc = "Toggle Diagnostic Lines", silent = true })
	vim.keymap.set("n", "<leader>lr", restart, { desc = "Restart Language Server", silent = true })
end

function M.setup()
	vim.api.nvim_create_autocmd(
		"LspAttach",
		{ group = vim.api.nvim_create_augroup("NativeLspAttach", { clear = true }), callback = attach }
	)
	require("mayon.ui.floats").setup()
	require("mayon.lsp.servers").setup()
	require("mayon.features.ai_completion").copilot_setup()
	-- Parameter names are opt-in with <leader>uh.
	vim.lsp.inlay_hint.enable(false)
	diagnostics()
	progress()
	vim.keymap.set("n", "<leader>uL", function()
		vim.lsp.codelens.enable(not vim.lsp.codelens.is_enabled({ bufnr = 0 }), { bufnr = 0 })
	end, { desc = "Toggle Code Lens", silent = true })
	vim.keymap.set("n", "<leader>ch", source_header, { desc = "Switch Source and Header", silent = true })
end

return M
