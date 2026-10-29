-- Keep native LSP requests, focus/close behavior and completion resolution.
local M = {}
local ready = false
local padding_ns = vim.api.nvim_create_namespace("MayonFloatPadding")

local function pad_buffer(buf)
	if not vim.api.nvim_buf_is_valid(buf) then
		return
	end
	vim.api.nvim_buf_clear_namespace(buf, padding_ns, 0, -1)
	for row, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
		vim.api.nvim_buf_set_extmark(buf, padding_ns, row - 1, 0, {
			virt_text = { { " ", "NormalFloat" } },
			virt_text_pos = "inline",
			priority = 20,
		})
		if line ~= "" then
			vim.api.nvim_buf_set_extmark(buf, padding_ns, row - 1, #line, {
				virt_text = { { " ", "NormalFloat" } },
				virt_text_pos = "inline",
				priority = 20,
			})
		end
	end
end

local function fit_padding(win, opts)
	if not vim.api.nvim_win_is_valid(win) then
		return
	end
	opts = opts or {}
	local cfg = vim.api.nvim_win_get_config(win)
	if cfg.relative == "" then
		return
	end
	local width = 0
	for _, line in ipairs(vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), 0, -1, false)) do
		width = math.max(width, vim.fn.strdisplaywidth(line))
	end
	local limit = math.max(1, math.min(opts.max_width or 64, vim.o.columns - 4))
	vim.api.nvim_win_set_config(win, { width = math.min(limit, math.max(cfg.width, width + 2)) })
	local height = vim.api.nvim_win_text_height(win, {}).all
	vim.api.nvim_win_set_config(win, { height = math.max(1, math.min(height, opts.max_height or 18, vim.o.lines - 4)) })
end

local function server()
	local clients = vim.lsp.get_clients({ bufnr = 0 })
	for _, client in ipairs(clients) do
		if client.name ~= "copilot" and client.name ~= "minuet" then
			return client.name
		end
	end
	return "LSP"
end

function M.options(kind, opts)
	return vim.tbl_extend("force", {
		border = "single",
		max_width = 64,
		max_height = 18,
		title = " " .. kind .. " · " .. server() .. " ",
		title_pos = "center",
	}, opts or {})
end

function M.hover()
	vim.lsp.buf.hover(M.options("hover"))
end
function M.signature()
	vim.lsp.buf.signature_help(M.options("signature"))
end

function M.setup()
	if ready then
		return
	end
	ready = true
	local original = vim.lsp.util.open_floating_preview
	vim.lsp.util.open_floating_preview = function(contents, syntax, opts)
		opts = vim.tbl_extend("keep", opts or {}, {
			border = "single",
			max_width = 64,
			max_height = 18,
			title_pos = "center",
		})
		local kind = opts.focus_id == "textDocument/hover" and "hover"
			or opts.focus_id == "textDocument/signatureHelp" and "signature"
		if not opts.title then
			kind = kind or (opts.focus_id == "vim.diagnostic.open_float" and "diagnostic") or "details"
			opts.title = " " .. kind .. " · " .. server() .. " "
			opts.title_pos = "center"
		end
		local lines = vim.deepcopy(contents)
		if kind then
			-- A Markdown rule separates the signature fence from its prose.
			local fences = 0
			for index, line in ipairs(lines) do
				if line:match("^```") then
					fences = fences + 1
				end
				if fences == 2 and index < #lines then
					if lines[index + 1] ~= "---" then
						table.insert(lines, index + 1, "---")
					end
					break
				end
			end
		end
		local buf, win = original(lines, syntax, opts)
		pad_buffer(buf)
		if win and vim.api.nvim_win_is_valid(win) then
			vim.wo[win].winhighlight =
				"Normal:NormalFloat,NormalNC:NormalFloat,FloatBorder:FloatBorder,FloatTitle:FloatTitle"
			vim.wo[win].wrap = true
			vim.wo[win].linebreak = true
			vim.wo[win].breakindent = true
			vim.wo[win].signcolumn = "no"
			-- FileType markdown enables prose spell checking; API documentation
			-- contains identifiers and should remain a quiet read-only preview.
			vim.wo[win].spell = false
			fit_padding(win, opts)
		end
		return buf, win
	end
end

return M
