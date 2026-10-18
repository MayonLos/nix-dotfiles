local M = {}

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
	map(bufnr, "gd", vim.lsp.buf.definition, "Go to definition")
	map(bufnr, "gD", vim.lsp.buf.declaration, "Go to declaration")
	map(bufnr, "grt", vim.lsp.buf.type_definition, "Type definition")
	map(bufnr, "gi", vim.lsp.buf.implementation, "Implementation")
	map(bufnr, "K", vim.lsp.buf.hover, "Hover")
	map(bufnr, "grx", vim.lsp.codelens.run, "Run codelens")
	map(bufnr, "<leader>rn", vim.lsp.buf.rename, "Rename symbol")
	map(bufnr, "<leader>ca", vim.lsp.buf.code_action, "Code action")
	map(bufnr, "<leader>wd", function()
		require("fzf-lua").diagnostics_workspace()
	end, "Workspace diagnostics")
end

local function diagnostics()
	vim.diagnostic.config({
		virtual_text = false,
		virtual_lines = { current_line = true },
		severity_sort = true,
		float = { border = "rounded", source = "if_many", header = "" },
	})

	vim.keymap.set("n", "[d", function()
		vim.diagnostic.jump({ count = -1, float = true })
	end, { desc = "Prev diagnostic", silent = true })
	vim.keymap.set("n", "]d", function()
		vim.diagnostic.jump({ count = 1, float = true })
	end, { desc = "Next diagnostic", silent = true })
	vim.keymap.set("n", "<leader>ll", function()
		local all = vim.diagnostic.config().virtual_lines == true
		vim.diagnostic.config({ virtual_lines = all and { current_line = true } or true })
	end, { desc = "Toggle diagnostic virtual lines (current line / all)", silent = true })
	vim.keymap.set("n", "<leader>lr", function()
		local bufnr = vim.api.nvim_get_current_buf()
		local ft = vim.bo[bufnr].filetype
		for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
			client:stop()
		end
		vim.defer_fn(function()
			vim.api.nvim_exec_autocmds("FileType", { pattern = ft })
		end, 500)
	end, { desc = "Restart LSP", silent = true })
end

local function progress()
	local active_progress = {}
	local group = vim.api.nvim_create_augroup("NativeLspProgress", { clear = true })
	vim.api.nvim_create_autocmd("LspProgress", {
		group = group,
		callback = function(event)
			local data = event.data or {}
			local client_id, params = data.client_id, data.params or {}
			local token, value = params.token, params.value or {}
			if client_id == nil or token == nil or type(value) ~= "table" then
				return
			end
			local client = vim.lsp.get_client_by_id(client_id)
			local client_name = client and client.name or "LSP"
			local tasks = active_progress[client_id]
			if value.kind == "begin" then
				tasks = tasks or {}
				active_progress[client_id] = tasks
				local title = value.title or "Progress"
				tasks[token] = { title = title, client_name = client_name }
				vim.notify(value.message or title, vim.log.levels.INFO, { title = client_name })
			elseif value.kind == "end" and tasks and tasks[token] then
				local task = tasks[token]
				tasks[token] = nil
				if next(tasks) == nil then
					active_progress[client_id] = nil
				end
				vim.notify(
					value.message or (task.title .. " completed"),
					vim.log.levels.INFO,
					{ title = task.client_name }
				)
			end
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
				if not client or not next(client.attached_buffers or {}) then
					active_progress[client_id] = nil
				end
			end)
		end,
	})

	local active_requests = {}
	local ai_group = vim.api.nvim_create_augroup("NativeCodeCompanionProgress", { clear = true })
	vim.api.nvim_create_autocmd("User", {
		group = ai_group,
		pattern = { "CodeCompanionRequestStarted", "CodeCompanionRequestFinished" },
		callback = function(event)
			local data = event.data or {}
			local id = data.id
			if id == nil then
				return
			end
			local interaction = data.interaction or data.strategy or "request"
			if interaction == "inline" then
				return
			end
			if event.match == "CodeCompanionRequestStarted" then
				local adapter = data.adapter or {}
				local name = adapter.formatted_name or adapter.name or "LLM"
				if adapter.model and adapter.model ~= "" then
					name = name .. " (" .. adapter.model .. ")"
				end
				local title = interaction .. " · " .. name
				active_requests[id] = { title = title }
				vim.notify("Requesting...", vim.log.levels.INFO, { title = title })
			elseif event.match == "CodeCompanionRequestFinished" then
				local request = active_requests[id]
				if not request then
					return
				end
				active_requests[id] = nil
				if data.status == "success" then
					vim.notify("Completed", vim.log.levels.INFO, { title = request.title })
				elseif data.status == "error" then
					vim.notify("Request failed", vim.log.levels.ERROR, { title = request.title })
				else
					vim.notify("Cancelled", vim.log.levels.WARN, { title = request.title })
				end
			end
		end,
	})
end

function M.setup()
	require("mayon.lsp.servers").setup()
	vim.lsp.inlay_hint.enable(true)
	diagnostics()
	progress()
	vim.keymap.set("n", "<leader>lh", source_header, { desc = "Switch source/header", silent = true })
	vim.api.nvim_create_autocmd(
		"LspAttach",
		{ group = vim.api.nvim_create_augroup("NativeLspAttach", { clear = true }), callback = attach }
	)
end

return M
