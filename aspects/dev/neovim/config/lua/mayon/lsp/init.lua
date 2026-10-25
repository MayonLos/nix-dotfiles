local M = {}
local progress_ids = {}

local function progress_id(client_id, token)
	return ("lsp:%s:%s:%s"):format(client_id, type(token), tostring(token))
end

local function publish_progress(client_id, id, value, status)
	local client = vim.lsp.get_client_by_id(client_id)
	local title = value.title or (client and client.name) or "LSP"
	local text = value.message or title
	local percent =
		math.max(0, math.min(100, math.floor(tonumber(value.percentage) or (status == "success" and 100 or 0))))
	vim.api.nvim_echo({ { tostring(text) } }, false, {
		kind = "progress",
		id = id,
		source = "lsp",
		title = tostring(title),
		status = status,
		percent = percent,
		data = { client_id = client_id },
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

			local status
			if value.kind == "begin" or value.kind == "report" then
				status = "running"
			elseif value.kind == "end" then
				status = "success"
			else
				return
			end

			local id = progress_id(client_id, token)
			if value.kind == "begin" then
				progress_ids[client_id] = progress_ids[client_id] or {}
				progress_ids[client_id][id] = true
			end
			publish_progress(client_id, id, value, status)
			if value.kind == "end" and progress_ids[client_id] then
				progress_ids[client_id][id] = nil
				if not next(progress_ids[client_id]) then
					progress_ids[client_id] = nil
				end
			end
		end,
	})

	vim.api.nvim_create_autocmd("LspDetach", {
		group = group,
		callback = function(event)
			local client_id = (event.data or {}).client_id
			if client_id == nil or not progress_ids[client_id] then
				return
			end
			vim.schedule(function()
				local client = vim.lsp.get_client_by_id(client_id)
				if client and next(client.attached_buffers or {}) then
					return
				end
				for id in pairs(progress_ids[client_id] or {}) do
					publish_progress(client_id, id, { message = "" }, "cancel")
				end
				progress_ids[client_id] = nil
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

local function attach(event)
	local bufnr = event.buf
	local client = vim.lsp.get_client_by_id(event.data and event.data.client_id)
	if not client then
		return
	end
	map(bufnr, "gd", vim.lsp.buf.definition, "跳到定义")
	map(bufnr, "grr", function()
		Snacks.picker.lsp_references()
	end, "查找引用 · preview")
	map(bufnr, "gK", function()
		require("mayon.ui.floats").signature()
	end, "查看函数签名")
	map(bufnr, "gD", vim.lsp.buf.declaration, "跳到声明")
	map(bufnr, "grt", vim.lsp.buf.type_definition, "跳到类型定义")
	map(bufnr, "gi", vim.lsp.buf.implementation, "跳到实现")
	map(bufnr, "K", function()
		local opts = require("mayon.ui.floats").options("hover")
		opts.title_pos = "center"
		vim.lsp.buf.hover(opts)
	end, "查看悬浮文档")
	map(bufnr, "grx", vim.lsp.codelens.run, "运行代码透镜")
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
	if supports("textDocument/signatureHelp") then
		local group = vim.api.nvim_create_augroup("MayonSignatureHelp" .. bufnr, { clear = true })
		vim.api.nvim_create_autocmd("InsertCharPre", {
			group = group,
			buffer = bufnr,
			callback = function()
				if vim.v.char == "(" or vim.v.char == "," then
					vim.schedule(function()
						if vim.api.nvim_buf_is_valid(bufnr) and vim.api.nvim_get_current_buf() == bufnr then
							local opts = require("mayon.ui.floats").options("signature")
							opts.title_pos = "center"
							vim.lsp.buf.signature_help(opts)
						end
					end)
				end
			end,
		})
	end
end

local function diagnostics()
	require("mayon.ui.icons").diagnostics()
	vim.diagnostic.config({
		virtual_text = false,
		virtual_lines = false,
		severity_sort = true,
		float = { border = "rounded", source = "if_many", header = "", title = " diagnostics ", title_pos = "center" },
	})

	vim.keymap.set("n", "<leader>ll", function()
		local all = vim.diagnostic.config().virtual_lines == true
		vim.diagnostic.config({ virtual_lines = all and { current_line = true } or true })
	end, { desc = "切换诊断虚拟行", silent = true })
	vim.keymap.set("n", "<leader>lr", function()
		local bufnr = vim.api.nvim_get_current_buf()
		local ft = vim.bo[bufnr].filetype
		for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
			client:stop()
		end
		vim.defer_fn(function()
			vim.api.nvim_exec_autocmds("FileType", { pattern = ft })
		end, 500)
	end, { desc = "重启语言服务", silent = true })
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
	end, { desc = "切换代码透镜", silent = true })
	vim.keymap.set("n", "<leader>ch", source_header, { desc = "切换源文件与头文件", silent = true })
end

return M
