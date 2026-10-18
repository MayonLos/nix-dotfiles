local M = {}

function M.setup()
	local border = { style = "rounded", padding = { 0, 1 } }
	require("noice").setup({
		notify = { enabled = false },
		messages = { view = "mini", view_error = "mini", view_warn = "mini" },
		popupmenu = { enabled = false },
		lsp = {
			progress = { enabled = false },
			override = {
				["vim.lsp.util.convert_input_to_markdown_lines"] = true,
				["vim.lsp.util.stylize_markdown"] = true,
			},
		},
		presets = {
			bottom_search = true,
			command_palette = true,
			long_message_to_split = true,
			lsp_doc_border = true,
			inc_rename = false,
		},
		views = {
			cmdline_popup = { border = border },
			hover = { border = border },
			popup = { border = border },
			mini = { win_options = { winblend = 0 } },
		},
		routes = {
			{ filter = { event = "msg_show", kind = "search_count" }, opts = { skip = true } },
			{
				filter = {
					event = "msg_show",
					any = {
						{ find = "%d+L, %d+B" },
						{ find = "; after #%d+" },
						{ find = "; before #%d+" },
						{ find = "%d fewer lines" },
						{ find = "%d more lines" },
						{ find = "written" },
					},
				},
				opts = { skip = true },
			},
		},
	})
end

return M
