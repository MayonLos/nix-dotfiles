local M = {}

local function setup()
	local install_dir = vim.fn.stdpath("data") .. "/site"
	-- Neovim caches existing runtime directories. Create the conventional site
	-- before registering it, so first-run health/queries see the same path.
	vim.fn.mkdir(install_dir, "p")
	require("nvim-treesitter").setup({ install_dir = install_dir })
	-- Octave files use the installed MATLAB grammar; no Octave grammar exists.
	vim.treesitter.language.register("matlab", "octave")
	vim.opt.foldenable = true
	vim.opt.foldlevelstart = 99

	local group = vim.api.nvim_create_augroup("MayonTreesitter", { clear = true })
	local function attach(args)
		local buf = args.buf
		if vim.bo[buf].filetype == "bigfile" or vim.b[buf].ts_highlight == false then
			return
		end
		vim.bo[buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
		require("mayon.features.folds").apply(buf)
		local ft = vim.bo[buf].filetype
		local lang = vim.treesitter.language.get_lang(ft) or ft
		pcall(vim.treesitter.start, buf, lang)
	end
	vim.api.nvim_create_autocmd("FileType", { group = group, callback = attach })
	-- FileType can precede the first BufReadPost, before this handler exists.
	if vim.bo.filetype ~= "" then
		attach({ buf = vim.api.nvim_get_current_buf() })
	end
end

return { { "nvim-treesitter", event = { "BufReadPost", "BufNewFile" }, after = setup } }
