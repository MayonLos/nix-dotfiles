-- Fidget progress notifications for CodeCompanion requests.
-- Inline requests are skipped: they get a buffer indicator from cc_inline_indicator.lua.
local M = { handles = {} }

local progress

local function adapter_label(adapter)
	adapter = adapter or {}
	local label = adapter.formatted_name or adapter.name or "LLM"
	if adapter.model and adapter.model ~= "" then
		label = label .. " (" .. adapter.model .. ")"
	end
	return label
end

local function on_started(data)
	M.handles[data.id] = progress.handle.create({
		title = " " .. (data.interaction or data.strategy or "request"),
		message = "Requesting...",
		lsp_client = { name = adapter_label(data.adapter) },
	})
end

local function on_finished(data)
	local handle = M.handles[data.id]
	if not handle then
		return
	end
	M.handles[data.id] = nil
	if data.status == "success" then
		handle.message = "Completed"
	elseif data.status == "error" then
		handle.message = " Error"
	else
		handle.message = "󰜺 Cancelled"
	end
	handle:finish()
end

function M.setup()
	local ok
	ok, progress = pcall(require, "fidget.progress")
	if not ok then
		return
	end
	vim.api.nvim_create_autocmd("User", {
		group = vim.api.nvim_create_augroup("CodeCompanionFidget", { clear = true }),
		pattern = { "CodeCompanionRequestStarted", "CodeCompanionRequestFinished" },
		callback = function(args)
			local data = args.data or {}
			if not data.id or (data.interaction or data.strategy) == "inline" then
				return
			end
			if args.match == "CodeCompanionRequestStarted" then
				on_started(data)
			else
				on_finished(data)
			end
		end,
	})
end

return M
