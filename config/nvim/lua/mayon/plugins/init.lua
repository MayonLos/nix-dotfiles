local M = {}

function M.setup()
	require("mayon.plugins.ai").setup()
	require("mayon.plugins.completion").setup()
	require("mayon.plugins.editing").setup()
	require("mayon.plugins.treesitter").setup()
	require("mayon.plugins.formatting").setup()
	require("mayon.plugins.git").setup()
	require("mayon.plugins.navigation").setup()
	require("mayon.plugins.utility").setup()
	require("mayon.plugins.lint").setup()
end

return M
