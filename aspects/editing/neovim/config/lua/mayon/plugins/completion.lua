local M = {}

function M.setup()
	require("blink-cmp").setup({
		appearance = { kind_icons = require("mayon.kinds") },
		enabled = function()
			return vim.bo.filetype ~= "bigfile"
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
				min_width = 28,
				max_height = 9,
				border = "rounded",
				draw = {
					padding = 1,
					gap = 1,
					treesitter = { "lsp" },
					columns = {
						{ "kind_icon" },
						{ "label", "label_description", gap = 1 },
						{ "source_name" },
					},
					components = {
						label = { width = { fill = true, max = 48 } },
						label_description = { width = { max = 22 }, ellipsis = true },
						source_name = {
							width = { max = 14 },
							ellipsis = true,
							text = function(ctx)
								local short_names = {
									buffer = "Buf",
									path = "Path",
									snippets = "Snip",
									["lua modules"] = "Lua",
								}
								return short_names[ctx.source_name:lower()] or ctx.source_name
							end,
						},
					},
				},
			},
			trigger = { show_in_snippet = false },
			documentation = {
				auto_show = true,
				window = { max_width = 60, max_height = 18, border = "rounded" },
			},
			accept = { auto_brackets = { enabled = false } },
		},
		sources = {
			per_filetype = {
				codecompanion = { "codecompanion", inherit_defaults = true },
				lua = { "lazydev", inherit_defaults = true },
			},
			providers = {
				lazydev = {
					name = "Lua Modules",
					module = "lazydev.integrations.blink",
					score_offset = 100,
				},
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
