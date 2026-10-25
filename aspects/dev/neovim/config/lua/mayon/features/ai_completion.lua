-- One completion owner at a time; credentials remain environment/runtime state.
local M = { provider = "copilot", busy = false, epoch = 0, pending = 0 }
local choices = { "copilot", "deepseek", "off" }
local warned = {}
function M.require_deepseek_key()
	if type(vim.env.DEEPSEEK_API_KEY) == "string" and vim.env.DEEPSEEK_API_KEY ~= "" then
		return true
	end
	vim.notify(
		"DeepSeek 需要环境变量 DEEPSEEK_API_KEY；请在终端配置后重启 Neovim",
		vim.log.levels.WARN,
		{
			title = "AI 助手",
		}
	)
	return false
end
local function redraw()
	vim.cmd.redrawstatus()
end
function M.warn(message)
	if warned[message] then
		return
	end
	warned[message] = true
	vim.schedule(function()
		vim.notify(message .. "；用 <leader>au 或 :AICompletion deepseek 切换兜底", vim.log.levels.WARN)
	end)
end
function M.allowed(buf)
	buf = buf or vim.api.nvim_get_current_buf()
	return vim.bo[buf].buftype == ""
		and vim.bo[buf].filetype ~= "bigfile"
		and vim.b[buf].completion ~= false
		and vim.g.completion ~= false
end
function M.set(provider)
	assert(vim.tbl_contains(choices, provider), "unknown AI completion provider: " .. tostring(provider))
	M.epoch = M.epoch + 1
	M.provider = provider
	M.busy = false
	vim.g.sidekick_nes = provider == "copilot"
	vim.lsp.inline_completion.enable(provider == "copilot")
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_loaded(buf) and not M.allowed(buf) then
			vim.lsp.inline_completion.enable(false, { bufnr = buf })
		end
		vim.b[buf].minuet_virtual_text_auto_trigger = provider == "deepseek" and M.allowed(buf)
	end
	if package.loaded["sidekick.nes"] then
		require("sidekick.nes").clear()
	end
	if provider == "deepseek" then
		require("lz.n").trigger_load("minuet-ai.nvim")
		if not vim.env.DEEPSEEK_API_KEY or vim.env.DEEPSEEK_API_KEY == "" then
			vim.notify("DeepSeek 需要环境变量 DEEPSEEK_API_KEY", vim.log.levels.WARN)
		end
	end
	if package.loaded["minuet.virtualtext"] then
		require("minuet.virtualtext").action.dismiss()
	end
	redraw()
	return provider
end
function M.cycle()
	local index = 1
	for i, name in ipairs(choices) do
		if name == M.provider then
			index = i
		end
	end
	local provider = M.set(choices[index % #choices + 1])
	vim.notify("AI 补全：" .. provider)
end
function M.accept()
	if vim.fn.pumvisible() == 1 or not M.allowed() then
		return false
	end
	if M.provider == "copilot" then
		return vim.lsp.inline_completion.get()
	elseif M.provider == "deepseek" and package.loaded["minuet.virtualtext"] then
		local action = require("minuet.virtualtext").action
		if action.is_visible() then
			action.accept()
			return true
		end
	end
	return false
end
local function first_word(text)
	return text:match("^%s*[%w_]+") or text:match("^%s*[^%w_%s]+") or text:match("^%s+") or ""
end
function M.accept_word()
	if vim.fn.pumvisible() == 1 or not M.allowed() then
		return false
	end
	if M.provider == "copilot" then
		return vim.lsp.inline_completion.get({
			on_accept = function(item)
				local text = item.insert_text
				if type(text) ~= "string" then
					text = tostring(require("vim.lsp._snippet_grammar").parse(text.value))
				end
				local cursor = vim.api.nvim_win_get_cursor(0)
				local prefix = ""
				if item.range then
					local row, col = item.range:to_extmark()
					prefix = table.concat(vim.api.nvim_buf_get_text(0, row, col, cursor[1] - 1, cursor[2], {}), "\n")
					item.range = vim.range(0, row, col, cursor[1] - 1, cursor[2])
				end
				item.insert_text = prefix .. first_word(text:sub(#prefix + 1))
				item.command = nil -- A partial acceptance is not a full-suggestion action.
				return item
			end,
		})
	elseif M.provider == "deepseek" and package.loaded["minuet.virtualtext"] then
		local vt = require("minuet.virtualtext")
		if not vt.action.is_visible() then
			return false
		end
		-- Minuet 0.9 exposes line acceptance only. Read its rendered first line
		-- for word acceptance without reaching into its private context table.
		local marks = vim.api.nvim_buf_get_extmarks(0, vt.ns_id, 0, -1, { details = true })
		local details = marks[1] and marks[1][4] or {}
		local chunks = details.virt_text
		local lines = { chunks and chunks[1] and chunks[1][1] or "" }
		for _, line in ipairs(details.virt_lines or {}) do
			lines[#lines + 1] = line[1][1]
		end
		local text = table.concat(lines, "\n")
		text = text:gsub(" %(%d+/%d+%)$", "")
		local word = first_word(text)
		if word == "" then
			return false
		end
		vim.schedule(function()
			vim.api.nvim_paste(word, false, -1)
		end)
		return true
	end
	return false
end
function M.dismiss()
	local visible = false
	if M.provider == "copilot" then
		visible = vim.lsp.inline_completion.get({
			on_accept = function()
				return nil
			end,
		})
	elseif package.loaded["minuet.virtualtext"] then
		local action = require("minuet.virtualtext").action
		visible = action.is_visible()
		vim.schedule(action.dismiss)
	end
	return visible
end
function M.step(direction)
	if M.provider == "copilot" then
		vim.lsp.inline_completion.select({ count = direction == "next" and 1 or -1 })
	elseif M.provider == "deepseek" and M.allowed() and vim.env.DEEPSEEK_API_KEY and vim.env.DEEPSEEK_API_KEY ~= "" then
		require("lz.n").trigger_load("minuet-ai.nvim")
		require("minuet.virtualtext").action[direction]()
	end
end
local copilot_ready = false
function M.copilot_setup()
	if copilot_ready then
		return
	end
	copilot_ready = true
	vim.lsp.config("copilot", {
		cmd = { require("mayon.generated").tools.copilot, "--stdio" },
		settings = { telemetry = { telemetryLevel = "off" } },
	})
	local group = vim.api.nvim_create_augroup("MayonInlineCompletion", { clear = true })
	vim.api.nvim_create_autocmd("LspAttach", {
		group = group,
		callback = function(ev)
			local client = vim.lsp.get_client_by_id(ev.data.client_id)
			if not client or client.name ~= "copilot" then
				return
			end
			vim.lsp.inline_completion.enable(M.provider == "copilot" and M.allowed(ev.buf), { bufnr = ev.buf })
			require("lz.n").trigger_load("sidekick.nvim")
		end,
	})
	vim.api.nvim_create_autocmd("CompleteChanged", {
		group = group,
		callback = function(ev)
			if vim.fn.pumvisible() == 1 then
				vim.schedule(function()
					if
						vim.api.nvim_buf_is_valid(ev.buf)
						and vim.api.nvim_get_current_buf() == ev.buf
						and vim.fn.pumvisible() == 1
					then
						vim.lsp.inline_completion.enable(false, { bufnr = ev.buf })
					end
				end)
			end
		end,
	})
	vim.api.nvim_create_autocmd("CompleteDone", {
		group = group,
		callback = function(ev)
			vim.lsp.inline_completion.enable(M.provider == "copilot" and M.allowed(ev.buf), { bufnr = ev.buf })
		end,
	})
	vim.lsp.inline_completion.enable(M.provider == "copilot")
	vim.lsp.enable("copilot")
end
-- Guard asynchronous completion callbacks across provider and buffer changes.
function M.guard(callback)
	local epoch, buf = M.epoch, vim.api.nvim_get_current_buf()
	return function(data)
		if
			M.epoch == epoch
			and M.provider == "deepseek"
			and vim.api.nvim_get_current_buf() == buf
			and M.allowed(buf)
		then
			callback(data)
		end
	end
end
function M.wrap_backend(complete)
	return function(context, callback)
		if
			M.provider ~= "deepseek"
			or not M.allowed()
			or not vim.env.DEEPSEEK_API_KEY
			or vim.env.DEEPSEEK_API_KEY == ""
		then
			return
		end
		return complete(context, M.guard(callback))
	end
end
function M.minuet_setup()
	require("minuet").setup({
		provider = "openai_fim_compatible",
		notify = false,
		n_completions = 2,
		provider_options = {
			openai_fim_compatible = {
				name = "deepseek",
				api_key = "DEEPSEEK_API_KEY",
				end_point = "https://api.deepseek.com/beta/completions",
				optional = { max_tokens = 256, top_p = 0.9 },
			},
		},
		virtualtext = { auto_trigger_ft = { "*" }, show_on_completion_menu = false, keymap = {} },
		enable_predicates = {
			function()
				return M.provider == "deepseek"
					and M.allowed()
					and vim.env.DEEPSEEK_API_KEY ~= nil
					and vim.env.DEEPSEEK_API_KEY ~= ""
			end,
		},
	})
	-- Minuet 0.9 checks predicates before dispatch, but not on response. Its
	-- public backend callback is wrapped to discard results after a switch.
	local backend = require("minuet.backends.openai_fim_compatible")
	backend.complete = M.wrap_backend(backend.complete)
	vim.api.nvim_create_autocmd("User", {
		group = vim.api.nvim_create_augroup("MayonMinuetProgress", { clear = true }),
		pattern = { "MinuetRequestStartedPre", "MinuetRequestFinished" },
		callback = function(ev)
			if ev.match == "MinuetRequestStartedPre" then
				M.pending = M.pending + ((ev.data or {}).n_requests or 1)
			else
				M.pending = math.max(0, M.pending - 1)
			end
			redraw()
		end,
	})
end
return M
