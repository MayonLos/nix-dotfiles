assert(vim.g.mayon_config_loaded and vim.g.colors_name == "onedark")
local mode = assert(vim.env.NVIM_CHECK_MODE)
if mode ~= "dev" then
	assert(package.loaded["mayon.generated_highlights"], "packaged editor must use its compiled theme")
else
	assert(not package.loaded["mayon.generated_highlights"], "development override must use the live theme adapter")
end
if mode == "reduced" then
	assert(require("mayon.generated").palette.reducedMotion)
	assert(not require("snacks").config.scroll.enabled)
	assert(not require("snacks").config.dim.animate.enabled)
	vim.api.nvim_exec_autocmds("User", { pattern = "MayonVeryLazy" })
elseif mode == "dev" then
	assert(vim.env.NVIM_CONFIG_DIR == vim.env.NVIM_EXPECTED_CONFIG_DIR)
	assert(require("mayon.generated").languages.servers.clangd)
elseif mode == "normal" then
	assert(vim.env.NVIM_CONFIG_DIR ~= "/invalid-config")
else
	error("Unknown wrapper check mode: " .. mode)
end
print("Wrapper mode passed: " .. mode)
