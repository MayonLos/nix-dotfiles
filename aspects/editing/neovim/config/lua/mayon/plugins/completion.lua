local M = {}

function M.setup()
	require("blink-cmp").setup({
		appearance = { kind_icons = require("mayon.kinds") },
		enabled = function()
			return not vim.b.mayon_bigfile
				and vim.bo.buftype ~= "prompt"
				and vim.b.completion ~= false
				and vim.g.completion ~= false
		end,
		keymap = {
			preset = "enter",
			["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
			["<C-e>"] = { "cancel", "fallback" },
			["<Up>"] = { "select_prev", "fallback" },
			["<Down>"] = { "select_next", "fallback" },
			["<C-b>"] = { "scroll_documentation_up", "fallback" },
			["<C-f>"] = { "scroll_documentation_down", "fallback" },
			["<Tab>"] = { "snippet_forward", "select_next", "fallback" },
			["<S-Tab>"] = { "snippet_backward", "select_prev", "fallback" },
			["<C-k>"] = { "show_signature", "hide_signature", "fallback" },
		},
		completion = {
			menu = {
				border = "rounded",
				draw = {
					padding = 1,
					gap = 1,
					treesitter = { "lsp" },
					columns = { { "label" }, { "kind_icon", "kind", gap = 1 }, { "source_name" } },
				},
			},
			trigger = { show_in_snippet = false },
			documentation = { auto_show = true, window = { border = "rounded" } },
			accept = { auto_brackets = { enabled = false } },
		},
		sources = {
			per_filetype = { codecompanion = { "codecompanion", inherit_defaults = true } },
			providers = {
				codecompanion = {
					name = "CodeCompanion",
					-- This proxy avoids loading CodeCompanion during ordinary completion.
					module = "mayon.plugins.cc_blink_proxy",
					score_offset = 100,
				},
				snippets = {
					opts = {
						search_paths = (function()
							-- Prefer this config's snippets, then discover package manifests.
							local paths = { vim.fn.stdpath("config") .. "/snippets" }
							local files = vim.api.nvim_get_runtime_file("snippets/package.json", true)
							if #files > 0 then
								local runtime_path = vim.fs.dirname(files[1])
								if runtime_path ~= paths[1] then
									table.insert(paths, runtime_path)
								end
							end
							return paths
						end)(),
					},
				},
			},
		},
		snippets = { preset = "default" },
		signature = { enabled = true, window = { border = "rounded" } },
	})
end

return M
