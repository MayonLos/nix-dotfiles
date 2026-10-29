local M = {}
function M.toggle()
	vim.g.mayon_breadcrumbs = not vim.g.mayon_breadcrumbs
	require("lz.n").trigger_load("dropbar.nvim")
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.g.mayon_breadcrumbs then
			require("dropbar.utils.bar").attach(vim.api.nvim_win_get_buf(win), win)
		elseif vim.api.nvim_win_get_config(win).relative == "" and vim.wo[win].winbar:find("dropbar", 1, true) then
			vim.wo[win].winbar = ""
		end
	end
end
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
				return vim.g.mayon_breadcrumbs == true
					and vim.api.nvim_win_is_valid(win)
					and vim.api.nvim_win_get_config(win).relative == ""
					and vim.bo[buf].buftype == ""
					and vim.bo[buf].filetype ~= "snacks_dashboard"
					and vim.bo[buf].filetype ~= "bigfile"
			end,
			padding = { left = 1, right = 1 },
		},
		menu = { win_configs = { border = "single" } },
	})
end
return M
