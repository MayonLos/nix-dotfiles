local M = {}

local function resize_height(delta)
	local n = vim.v.count1 * delta
	vim.cmd("resize " .. (n >= 0 and ("+" .. n) or tostring(n)))
end

local function resize_width(delta)
	local n = vim.v.count1 * delta
	vim.cmd("vertical resize " .. (n >= 0 and ("+" .. n) or tostring(n)))
end

function M.setup()
	local Snacks = require("snacks")
	vim.keymap.set("n", "gx", function()
		require("mayon.features.urls").gx()
	end, { desc = "Open URL under cursor" })
	vim.keymap.set("x", "gx", function()
		require("mayon.features.urls").gx_visual()
	end, { desc = "Open URLs in selection" })
	vim.keymap.set("n", "<leader>fu", function()
		require("mayon.features.urls").pick_buffer()
	end, { desc = "URLs in buffer" })
	vim.keymap.set("n", "<leader>fU", function()
		require("mayon.features.urls").pick_dir()
	end, { desc = "URLs under cwd" })
	for _, spec in ipairs({
		{ "<leader>xx", "diagnostics toggle", "Diagnostics (project)" },
		{ "<leader>xX", "diagnostics toggle filter.buf=0", "Diagnostics (buffer)" },
		{ "<leader>xs", "symbols toggle", "Symbol outline" },
		{ "<leader>xl", "lsp toggle win.position=right", "LSP locations" },
		{ "<leader>xq", "qflist toggle", "Quickfix list" },
	}) do
		vim.keymap.set("n", spec[1], "<cmd>Trouble " .. spec[2] .. "<cr>", { desc = spec[3] })
	end
	vim.keymap.set("n", "<leader>ub", function()
		local buf = vim.api.nvim_get_current_buf()
		local row, col = unpack(vim.api.nvim_win_get_cursor(0))
		local line = vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
		local offset = 0
		while true do
			local word, first, last = unpack(vim.fn.matchstrpos(line, [[\k\+]], offset))
			if first < 0 or first > col then
				break
			end

			if first <= col and col < last then
				local prefix = line:sub(1, first)
				local suffix = line:sub(last + 1)
				local has_keyword_prefix = prefix:sub(-1) == "_" or vim.fn.matchstr(prefix, [[\k$]]) ~= ""
				local has_keyword_suffix = suffix:sub(1, 1) == "_" or vim.fn.matchstr(suffix, [[^\k]]) ~= ""
				local replacement = ({ ["true"] = "false", ["false"] = "true" })[word]

				if replacement and not has_keyword_prefix and not has_keyword_suffix then
					vim.api.nvim_buf_set_text(buf, row - 1, first, row - 1, last, { replacement })
				end
				break
			end

			offset = last
		end
	end, { desc = "Toggle true/false under cursor" })
	vim.keymap.set("n", "<leader>uu", function()
		vim.cmd.packadd("nvim.undotree")
		vim.cmd.Undotree()
	end, { desc = "Toggle undo tree" })
	vim.keymap.set("n", "<leader>uc", function()
		local filter = { bufnr = vim.api.nvim_get_current_buf() }
		local colors = vim.lsp.document_color
		colors.enable(not colors.is_enabled(filter), filter)
	end, { desc = "Toggle LSP colour swatches" })
	vim.keymap.set("n", "<leader>gg", function()
		Snacks.lazygit()
	end, { desc = "Lazygit" })
	vim.keymap.set({ "n", "v" }, "<leader>go", function()
		Snacks.gitbrowse()
	end, { desc = "Open line on remote" })
	vim.keymap.set("n", "<leader>fR", function()
		Snacks.rename.rename_file()
	end, { desc = "Rename file (LSP-aware)" })
	vim.keymap.set("n", "<leader>e", function()
		Snacks.explorer()
	end, { desc = "File tree" })
	vim.keymap.set({ "n", "x" }, "[i", function()
		Snacks.scope.jump({ bottom = false })
	end, { desc = "Jump to top of scope" })
	vim.keymap.set({ "n", "x" }, "]i", function()
		Snacks.scope.jump({ bottom = true })
	end, { desc = "Jump to bottom of scope" })
	vim.keymap.set("n", "<leader>us", function()
		require("mayon.features.scratch").scratch()
	end, { desc = "Scratch buffer" })
	vim.keymap.set("n", "<leader>uS", function()
		require("mayon.features.scratch").scratch_select()
	end, { desc = "Select scratch buffer" })
	vim.keymap.set("n", "<leader>uz", function()
		Snacks.zen()
	end, { desc = "Zen mode" })
	vim.keymap.set("n", "<leader>ud", function()
		Snacks.dim()
	end, { desc = "Dim inactive scope" })
	vim.keymap.set("n", "<leader>un", function()
		Snacks.notifier.show_history()
	end, { desc = "Notification history" })
	vim.keymap.set("n", "<leader>uw", function()
		Snacks.toggle.option("wrap", { name = "Wrap" }):toggle()
	end, { desc = "Toggle wrap" })
	vim.keymap.set("n", "<leader>up", function()
		Snacks.toggle.option("spell", { name = "Spelling" }):toggle()
	end, { desc = "Toggle spelling" })
	vim.keymap.set("n", "<leader>ur", function()
		Snacks.toggle.option("relativenumber", { name = "Relative number" }):toggle()
	end, { desc = "Toggle relative number" })
	vim.keymap.set("n", "<leader>ux", function()
		Snacks.toggle.diagnostics():toggle()
	end, { desc = "Toggle diagnostics" })
	vim.keymap.set("n", "<leader>ui", function()
		Snacks.toggle.inlay_hints():toggle()
	end, { desc = "Toggle inlay hints" })
	vim.keymap.set("n", "<leader>ut", function()
		Snacks.toggle.treesitter():toggle()
	end, { desc = "Toggle Treesitter" })
	vim.keymap.set("n", "<leader>uh", "<cmd>NoiceHistory<cr>", { desc = "Message history" })
	vim.keymap.set("n", "<leader>uD", function()
		vim.cmd("NoiceDismiss")
		Snacks.notifier.hide()
	end, { desc = "Dismiss messages and notifications" })
	vim.keymap.set("n", "<leader>ue", "<cmd>NoiceErrors<cr>", { desc = "Error messages" })
	vim.keymap.set({ "n", "i" }, "<C-s>", "<cmd>w<cr>", { desc = "Save file" })
	vim.keymap.set("n", "<leader>q", "<cmd>q<cr>", { desc = "Quit Neovim" })
	vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })
	vim.keymap.set("n", "<Tab>", "<cmd>bnext<cr>", { desc = "Next buffer" })
	vim.keymap.set("n", "<S-Tab>", "<cmd>bprevious<cr>", { desc = "Previous buffer" })
	vim.api.nvim_create_user_command("ImagePreview", function(args)
		if args.args ~= "" then
			vim.cmd.edit(vim.fn.fnameescape(vim.fn.expand(args.args)))
		else
			Snacks.image.hover()
		end
	end, { nargs = "?", complete = "file", desc = "Preview image or formula under cursor" })
	vim.keymap.set("n", "<leader>bd", function()
		Snacks.bufdelete()
	end, { desc = "Close current buffer" })
	vim.keymap.set("n", "<leader>ws", "<cmd>split<cr>", { desc = "Horizontal Split" })
	vim.keymap.set("n", "<leader>wv", "<cmd>vsplit<cr>", { desc = "Vertical Split" })
	vim.keymap.set("n", "<C-h>", "<C-w>h", { desc = "Move to left window" })
	vim.keymap.set("n", "<C-j>", "<C-w>j", { desc = "Move to lower window" })
	vim.keymap.set("n", "<C-k>", "<C-w>k", { desc = "Move to upper window" })
	vim.keymap.set("n", "<C-l>", "<C-w>l", { desc = "Move to right window" })
	vim.keymap.set("n", "<C-Up>", function()
		resize_height(2)
	end, { desc = "Increase window height", silent = true })
	vim.keymap.set("n", "<C-Down>", function()
		resize_height(-2)
	end, { desc = "Decrease window height", silent = true })
	vim.keymap.set("n", "<C-Right>", function()
		resize_width(3)
	end, { desc = "Increase window width", silent = true })
	vim.keymap.set("n", "<C-Left>", function()
		resize_width(-3)
	end, { desc = "Decrease window width", silent = true })
end

return M
