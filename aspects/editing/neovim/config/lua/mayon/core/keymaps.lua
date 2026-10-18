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
	vim.keymap.set("n", "<leader>xx", function()
		vim.diagnostic.setqflist({ title = "All diagnostics", open = true })
	end, { desc = "Diagnostics (all known buffers)" })
	vim.keymap.set("n", "<leader>xX", function()
		vim.diagnostic.setloclist({ title = "Buffer diagnostics", open = true })
	end, { desc = "Diagnostics (current buffer)" })
	vim.keymap.set("n", "<leader>xs", function()
		require("fzf-lua").lsp_document_symbols()
	end, { desc = "Document symbols" })
	vim.keymap.set("n", "<leader>xl", function()
		require("fzf-lua").lsp_finder()
	end, { desc = "LSP locations (definitions, references, implementations)" })
	vim.keymap.set("n", "<leader>xq", function()
		local quickfix_open = false
		for _, win in ipairs(vim.fn.getwininfo()) do
			if win.tabnr == vim.fn.tabpagenr() and win.quickfix == 1 and win.loclist == 0 then
				quickfix_open = true
				break
			end
		end
		vim.cmd(quickfix_open and "cclose" or "copen")
	end, { desc = "Toggle quickfix list" })
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
		require("mayon.files").lazygit()
	end, { desc = "Lazygit" })
	vim.keymap.set({ "n", "v" }, "<leader>go", function()
		require("mayon.files").gitbrowse()
	end, { desc = "Open line on remote" })
	vim.keymap.set("n", "<leader>fR", function()
		require("mayon.files").rename()
	end, { desc = "Rename file (LSP-aware)" })
	vim.keymap.set("n", "<leader>e", function()
		require("mayon.files").explorer()
	end, { desc = "File tree" })
	vim.keymap.set({ "n", "x" }, "[i", function()
		require("mayon.editor").scope_jump({ bottom = false })
	end, { desc = "Jump to top of scope" })
	vim.keymap.set({ "n", "x" }, "]i", function()
		require("mayon.editor").scope_jump({ bottom = true })
	end, { desc = "Jump to bottom of scope" })
	vim.keymap.set("n", "<leader>us", function()
		require("mayon.files").scratch()
	end, { desc = "Scratch buffer" })
	vim.keymap.set("n", "<leader>uS", function()
		require("mayon.files").scratch_select()
	end, { desc = "Select scratch buffer" })
	vim.keymap.set("n", "<leader>uz", function()
		require("mayon.editor").zen()
	end, { desc = "Zen mode" })
	vim.keymap.set("n", "<leader>ud", function()
		require("mayon.editor").dim()
	end, { desc = "Dim inactive scope" })
	vim.keymap.set("n", "<leader>un", function()
		require("mayon.ui").history()
	end, { desc = "Notification history" })
	vim.keymap.set("n", "<leader>uw", function()
		require("mayon.editor").toggle("wrap")
	end, { desc = "Toggle wrap" })
	vim.keymap.set("n", "<leader>up", function()
		require("mayon.editor").toggle("spell")
	end, { desc = "Toggle spelling" })
	vim.keymap.set("n", "<leader>ur", function()
		require("mayon.editor").toggle("relativenumber")
	end, { desc = "Toggle relative number" })
	vim.keymap.set("n", "<leader>ux", function()
		require("mayon.editor").toggle("diagnostics")
	end, { desc = "Toggle diagnostics" })
	vim.keymap.set("n", "<leader>ui", function()
		require("mayon.editor").toggle("inlay_hints")
	end, { desc = "Toggle inlay hints" })
	vim.keymap.set("n", "<leader>ut", function()
		require("mayon.editor").toggle("treesitter")
	end, { desc = "Toggle Treesitter" })
	vim.keymap.set("n", "<leader>uh", "<cmd>NoiceHistory<cr>", { desc = "Message history" })
	vim.keymap.set("n", "<leader>uD", function()
		vim.cmd("NoiceDismiss")
		require("mayon.ui").dismiss()
	end, { desc = "Dismiss messages and notifications" })
	vim.keymap.set("n", "<leader>ue", "<cmd>NoiceErrors<cr>", { desc = "Error messages" })
	vim.keymap.set({ "n", "i" }, "<C-s>", "<cmd>w<cr>", { desc = "Save file" })
	vim.keymap.set("n", "<leader>q", "<cmd>q<cr>", { desc = "Quit Neovim" })
	vim.keymap.set("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })
	vim.keymap.set("n", "<Tab>", "<cmd>bnext<cr>", { desc = "Next buffer" })
	vim.keymap.set("n", "<S-Tab>", "<cmd>bprevious<cr>", { desc = "Previous buffer" })
	vim.keymap.set("n", "<leader>bd", function()
		require("mayon.files").bufdelete()
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
