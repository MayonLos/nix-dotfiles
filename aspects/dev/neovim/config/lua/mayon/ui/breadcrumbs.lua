local M = {}
function M.setup()
	require("dropbar").setup({
		icons = {
			ui = { bar = { separator = " › " } },
			kinds = {
				symbols = {
					FunctionDeclaration = "󰊕 ",
					FunctionDefinition = "󰊕 ",
					MethodDefinition = "󰊕 ",
					ClassDeclaration = "󰠱 ",
				},
				file_icon = function(path)
					return require("mayon.ui.icons").get(path)
				end,
			},
		},
		sources = {
			lsp = {
				valid_symbols = {
					"Module",
					"Namespace",
					"Class",
					"Method",
					"Constructor",
					"Function",
					"Interface",
					"Enum",
					"Struct",
				},
			},
			treesitter = {
				valid_types = {
					"function_declaration",
					"function_definition",
					"method",
					"class",
					"class_declaration",
					"module",
					"struct",
					"enum",
				},
			},
		},
		bar = {
			enable = function(buf, win)
				return vim.api.nvim_win_is_valid(win)
					and vim.api.nvim_win_get_config(win).relative == ""
					and vim.bo[buf].buftype == ""
					and vim.bo[buf].filetype ~= "snacks_dashboard"
					and vim.bo[buf].filetype ~= "bigfile"
			end,
			padding = { left = 1, right = 1 },
		},
		menu = { win_configs = { border = "rounded" } },
	})
end
return M
