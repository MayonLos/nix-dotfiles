local function setup()
	require("mayon.features.native_completion").setup()
end

vim.api.nvim_create_autocmd({ "BufReadPre", "BufNewFile", "InsertEnter" }, {
	group = vim.api.nvim_create_augroup("MayonNativeCompletionLoader", { clear = true }),
	once = true,
	callback = setup,
})

return {}
