local M = {}

function M.setup()
	require("nvim-treesitter").setup({})
	-- Octave files use the installed MATLAB grammar; no Octave grammar exists.
	vim.treesitter.language.register("matlab", "octave")
	vim.opt.foldenable = true
	vim.opt.foldlevelstart = 99

	local group = vim.api.nvim_create_augroup("MayonTreesitter", { clear = true })
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		callback = function(args)
			local buf = args.buf
			if vim.bo[buf].filetype == "bigfile" or vim.b[buf].ts_highlight == false then
				return
			end
			vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
			vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
			vim.wo.foldmethod = "expr"
			local ft = vim.bo[buf].filetype
			local lang = vim.treesitter.language.get_lang(ft) or ft
			-- Keep LaTeX highlighting off to preserve the existing math-rendering boundary.
			if lang ~= "latex" then
				pcall(vim.treesitter.start, buf, lang)
			end
		end,
	})
end

return M
