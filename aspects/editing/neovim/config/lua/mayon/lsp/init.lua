local M = {}
local active_progress = {}
local progress_revision = 0

local function progress_message(tasks)
	local messages = {}
	local count = 0
	for _, task in pairs(tasks) do
		count = count + 1
		if #messages < 3 then
			messages[#messages + 1] = task.message or task.title
		end
	end
	if count > #messages then
		messages[#messages + 1] = string.format("… and %d more", count - #messages)
	end
	return table.concat(messages, "\n"), count
end

local function progress_status()
	local clients = {}
	for client_id, progress in pairs(active_progress) do
		local message, count = progress_message(progress.tasks)
		clients[#clients + 1] = {
			id = client_id,
			name = progress.client_name,
			message = message,
			task_count = count,
			updated_at = progress.updated_at,
		}
	end
	table.sort(clients, function(left, right)
		return left.updated_at < right.updated_at
	end)
	for _, client in ipairs(clients) do
		client.updated_at = nil
	end
	return clients
end

M.progress_status = progress_status

local function progress_changed()
	vim.api.nvim_exec_autocmds("User", {
		pattern = "MayonLspProgressChanged",
		modeline = false,
		data = progress_status(),
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
	local function update_progress(client_id, progress, done)
		local message, count = progress_message(progress.tasks)
		if done then
			message = "Ready"
		elseif count > 1 then
			message = string.format("%d tasks in progress\n%s", count, message)
		end
		local opts = { title = progress.client_name, silent = true }
		if progress.notification_id then
			opts.replace = progress.notification_id
		end
		progress.notification_id = vim.notify(message, vim.log.levels.INFO, opts)
		if not done then
			progress_revision = progress_revision + 1
			progress.updated_at = progress_revision
		end
		if done then
			active_progress[client_id] = nil
		end
		progress_changed()
	end
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
			local progress = active_progress[client_id]
			if value.kind == "begin" then
				progress = progress or { tasks = {}, client_name = client_name }
				active_progress[client_id] = progress
				progress.tasks[token] = { title = value.title or "Progress", message = value.message }
				update_progress(client_id, progress)
			elseif value.kind == "report" and progress and progress.tasks[token] then
				local task = progress.tasks[token]
				task.message = value.message or task.message
				update_progress(client_id, progress)
			elseif value.kind == "end" and progress and progress.tasks[token] then
				progress.tasks[token] = nil
				update_progress(client_id, progress, next(progress.tasks) == nil)
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
					local progress = active_progress[client_id]
					if progress then
						update_progress(client_id, progress, true)
					end
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
