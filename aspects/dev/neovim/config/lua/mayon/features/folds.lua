local M = {}
function M.text()
	local first = vim.fn.getline(vim.v.foldstart):gsub("^%s+", "")
	local count = vim.v.foldend - vim.v.foldstart + 1
	local summary = "  … " .. count .. " lines "
	local foldcolumn = tonumber(vim.wo.foldcolumn) or 0
	local width = math.max(1, vim.api.nvim_win_get_width(0) - foldcolumn - 4)
	local budget = math.max(1, width - vim.fn.strdisplaywidth(summary))
	if vim.fn.strdisplaywidth(first) > budget then
		first = vim.fn.strcharpart(first, 0, budget - 1) .. "…"
	end
	return {
		{ "  " .. first, "MayonFoldText" },
		{ summary, "MayonFoldCount" },
	}
end
function M.apply(buf)
	if vim.bo[buf].filetype == "bigfile" or vim.bo[buf].buftype ~= "" then
		return
	end
	local expr = "v:lua.vim.treesitter.foldexpr()"
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
		if client:supports_method("textDocument/foldingRange", buf) then
			expr = "v:lua.vim.lsp.foldexpr()"
			break
		end
	end
	for _, win in ipairs(vim.fn.win_findbuf(buf)) do
		vim.wo[win].foldmethod = "expr"
		vim.wo[win].foldexpr = expr
		vim.wo[win].foldtext = "v:lua.require'mayon.features.folds'.text()"
	end
end
function M.setup()
	vim.api.nvim_create_autocmd({ "LspAttach", "LspDetach", "BufWinEnter" }, {
		group = vim.api.nvim_create_augroup("MayonNativeFolds", { clear = true }),
		callback = function(ev)
			vim.schedule(function()
				if vim.api.nvim_buf_is_valid(ev.buf) then
					M.apply(ev.buf)
				end
			end)
		end,
	})
	vim.keymap.set("n", "zK", function()
		vim.cmd.normal({ "zo", bang = true })
	end, { desc = "Open Folded Context" })
end
return M
