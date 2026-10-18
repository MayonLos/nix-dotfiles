local M = {}

function M.setup()
	_G.slow_format_filetypes = {}
	_G.autoformat_disabled = function(bufnr)
		return vim.g.disable_autoformat or vim.b[bufnr].disable_autoformat
	end

	require("conform").setup({
		formatters_by_ft = {
			lua = { "stylua" },
			python = { "ruff_organize_imports", "ruff_format" },
			nix = { "nixfmt" },
			java = { "google-java-format" },
			c = { "clang-format" },
			cpp = { "clang-format" },
			bash = { "shfmt" },
			sh = { "shfmt" },
			tex = { "latexindent" },
			-- Keep this explicit so MATLAB LS handles .m files instead of `_`;
			-- its first format can exceed the 200ms synchronous save budget.
			matlab = { lsp_format = "fallback" },
			["_"] = { "squeeze_blanks", "trim_whitespace", "trim_newlines" },
		},
		format_on_save = function(bufnr)
			if _G.autoformat_disabled(bufnr) or _G.slow_format_filetypes[vim.bo[bufnr].filetype] then
				return
			end
			local function on_format(err)
				if err and err:match("timeout$") then
					_G.slow_format_filetypes[vim.bo[bufnr].filetype] = true
				end
			end
			return { timeout_ms = 200, lsp_format = "fallback" }, on_format
		end,
		format_after_save = function(bufnr)
			if _G.autoformat_disabled(bufnr) or not _G.slow_format_filetypes[vim.bo[bufnr].filetype] then
				return
			end
			return { lsp_format = "fallback" }
		end,
	})

	vim.keymap.set("n", "<leader>lf", function()
		require("conform").format({ async = true, lsp_format = "fallback" })
	end, { desc = "Format buffer (manual)" })
	vim.api.nvim_create_user_command("FormatDisable", function()
		vim.g.disable_autoformat = true
	end, { desc = "Disable autoformat-on-save" })
	vim.api.nvim_create_user_command("FormatEnable", function()
		vim.g.disable_autoformat = false
	end, { desc = "Enable autoformat-on-save" })
end

return M
