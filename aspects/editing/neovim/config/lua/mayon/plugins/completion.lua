local M = {}

local function setup()
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
			list = { selection = { preselect = false, auto_insert = false } },
			menu = {
				min_width = 28,
				max_height = 8,
				border = "rounded",
				draw = {
					padding = 1,
					gap = 1,
					treesitter = { "lsp" },
					columns = function()
						if vim.o.columns < 100 then
							return { { "kind_icon" }, { "label" } }
						elseif vim.o.columns < 140 then
							return { { "kind_icon" }, { "label" }, { "source_name" } }
						end
						return {
							{ "kind_icon" },
							{ "label", "label_description", gap = 1 },
							{ "source_name" },
						}
					end,
					components = {
						label = {
							width = {
								fill = true,
								max = function()
									return math.min(48, math.max(18, vim.o.columns - 32))
								end,
							},
						},
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
				auto_show_delay_ms = 300,
				window = {
					max_width = math.min(60, math.max(40, vim.o.columns - 8)),
					max_height = 14,
					border = "rounded",
				},
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
					module = "mayon.features.lua_blink_proxy",
					score_offset = 100,
				},
				codecompanion = {
					name = "CodeCompanion",
					-- This proxy avoids loading CodeCompanion during ordinary completion.
					module = "mayon.features.cc_blink_proxy",
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
	-- Blink creates kind-specific groups during setup; strip any inherited background
	-- so the selected row's single PmenuSel surface remains continuous.
	for name in pairs(vim.api.nvim_get_hl(0, {})) do
		if name:match("^BlinkCmpKind") or name:match("^BlinkCmpLabel") or name:match("^BlinkCmpSource") then
			local hl = vim.api.nvim_get_hl(0, { name = name, link = false })
			hl.bg = nil
			vim.api.nvim_set_hl(0, name, hl)
		end
	end
end

return { { "blink.cmp", event = { "BufReadPre", "BufNewFile", "InsertEnter", "CmdlineEnter" }, after = setup } }
