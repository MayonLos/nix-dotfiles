local M = {}
local sources = { "All", "Files", "Symbols", "Actions", "Text" }
function M.open(index, pattern)
	index = index or 1
	local S = require("snacks")
	local picker
	local function cycle(delta)
		local query = picker and picker.input:get() or ""
		if picker then
			picker:close()
		end
		M.open((index - 1 + delta) % #sources + 1, query)
	end
	local opts = {
		mayon_label = table.concat(
			vim.tbl_map(function(s)
				return s == sources[index] and ("• " .. s) or s
			end, sources),
			"  "
		),
		pattern = pattern,
		win = {
			input = {
				keys = {
					["<Tab>"] = {
						function()
							cycle(1)
						end,
						mode = { "i", "n" },
					},
					["<S-Tab>"] = {
						function()
							cycle(-1)
						end,
						mode = { "i", "n" },
					},
				},
			},
		},
	}
	if index == 1 then
		opts.multi = { "files", "buffers", "recent", "lsp_workspace_symbols", "keymaps" }
		picker = S.picker(opts)
	elseif index == 2 then
		picker = S.picker.files(opts)
	elseif index == 3 then
		picker = S.picker.lsp_workspace_symbols(opts)
	elseif index == 4 then
		picker = S.picker.keymaps(opts)
	else
		picker = S.picker.grep(opts)
	end
	return picker
end
return M
