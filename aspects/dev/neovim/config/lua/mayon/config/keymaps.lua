local M = {}

local function toggle_option(name, label)
	return function()
		require("snacks").toggle.option(name, { name = label }):toggle()
	end
end

local function map(mode, lhs, rhs, desc)
	vim.keymap.set(mode, lhs, rhs, { desc = desc, silent = true })
end

local function delete_to_trash()
	local path = vim.api.nvim_buf_get_name(0)
	if path == "" then
		vim.notify("当前缓冲区没有文件", vim.log.levels.WARN, { title = "回收站" })
		return
	end
	vim.ui.select({ "移入回收站", "取消" }, {
		prompt = "移入回收站：" .. vim.fn.fnamemodify(path, ":~:."),
		format_item = function(item)
			return item
		end,
	}, function(choice)
		if choice ~= "移入回收站" then
			return
		end
		local ok, err = require("mayon.features.fileops").trash(path)
		if not ok then
			vim.notify(err, vim.log.levels.ERROR, { title = "回收站" })
			return
		end
		vim.cmd.bdelete()
	end)
end

-- Splits that only hold tools (file tree, help, quickfix) and floating ui2
-- message windows do not count as editor windows; closing the last document
-- window would otherwise leave the tree alone or fail with E444.
local function close_smart()
	local api, tabline = vim.api, require("mayon.ui.tabline")
	if api.nvim_win_get_config(0).relative ~= "" then
		vim.cmd.close()
		return
	end
	local splits, documents = 0, 0
	for _, win in ipairs(api.nvim_tabpage_list_wins(0)) do
		if api.nvim_win_get_config(win).relative == "" then
			splits = splits + 1
			if tabline.is_document(api.nvim_win_get_buf(win)) then
				documents = documents + 1
			end
		end
	end
	local current_is_document = tabline.is_document(api.nvim_get_current_buf())
	if splits > 1 and (documents > 1 or not current_is_document) then
		vim.cmd.close()
	else
		require("snacks").bufdelete()
	end
end

local function terminal(position)
	return function()
		require("snacks").terminal(nil, {
			win = {
				style = "terminal",
				position = position,
				border = "single",
			},
		})
	end
end

local function project_root()
	local cwd = vim.fn.getcwd()
	local file = vim.api.nvim_buf_get_name(0)
	return vim.fs.root(file ~= "" and file or cwd, { ".git" }) or cwd
end

function M.setup()
	local Snacks = require("snacks")
	vim.g.mapleader = " "
	vim.g.maplocalleader = ","

	for key, action in pairs({
		["<A-1>"] = "project",
		["<A-2>"] = "commit",
		["<A-7>"] = "structure",
		["<A-F12>"] = "terminal",
	}) do
		map("n", key, function()
			require("mayon.ui.workspace").action(action)
		end, "工具窗口 · " .. action)
	end
	map("n", "<leader>?", function()
		require("lz.n").trigger_load("which-key.nvim")
		require("which-key").show({ global = true })
	end, "Show Keymaps")
	map("n", "<leader>;", function()
		Snacks.picker.lsp_symbols()
	end, "Pick Code Context")
	map("n", "<leader>rt", function()
		require("mayon.features.tasks").pick()
	end, "Pick Run Task")
	map("n", "<leader>rs", function()
		require("mayon.features.embedded").serial()
	end, "Open Serial Terminal")
	map("n", "<leader>sn", function()
		Snacks.picker.notifications()
	end, "Show Notifications")
	map("n", "<leader>ff", function()
		Snacks.picker.files()
	end, "Find Files")
	map("n", "<leader>rr", function()
		require("mayon.features.tasks").run_last()
	end, "Run Last Task")
	-- Top-level navigation and safe file actions.
	map("n", "<leader><leader>", function()
		require("mayon.ui.search").open()
	end, "Find Files and Text")
	map("n", "<leader>/", function()
		Snacks.picker.grep()
	end, "Search Text")
	map("n", "<leader>,", function()
		Snacks.picker.buffers()
	end, "Switch Buffers")
	map("n", "<leader>.", function()
		require("mayon.features.scratch").scratch()
	end, "Open Scratch Buffer")
	map("n", "<leader>w", "<cmd>write<cr>", "Save Buffer")
	map("n", "<leader>qq", close_smart, "Close Window or Buffer")
	map("n", "<leader>bd", function()
		Snacks.bufdelete()
	end, "Close Buffer")
	map("n", "<leader>bo", function()
		Snacks.bufdelete.other()
	end, "Close Other Buffers")
	-- Keep direct buffer positions available alongside the buffer picker.
	for index = 1, 9 do
		map("n", "<leader>" .. index, function()
			local buf = require("mayon.ui.tabline").buffers()[index]
			if buf then
				require("mayon.ui.tabline").select(buf)
			end
		end, "Jump to Buffer " .. index)
	end
	map("n", "<leader>qr", "<cmd>restart<cr>", "Restart Neovim")
	map("n", "<leader>e", function()
		local root = project_root()
		Snacks.explorer({ cwd = root, focus = "list" })
	end, "Open File Tree")
	map("n", "<leader>fe", function()
		vim.cmd("Oil")
	end, "Browse Directory")
	map("n", "<leader>fn", "<cmd>enew<cr>", "Create File")
	map("n", "<leader>fD", delete_to_trash, "Move to Trash")
	map("n", "<leader>fc", function()
		Snacks.picker.files({ cwd = vim.env.NVIM_CONFIG_DIR or vim.fn.stdpath("config") })
	end, "Open Neovim Config")
	map("n", "<leader>fR", function()
		Snacks.rename.rename_file()
	end, "Rename File Safely")
	map("n", "-", function()
		vim.cmd("Oil")
	end, "Browse Parent Directory")

	-- Search, symbols and picker history.
	map("n", "<leader>sw", function()
		Snacks.picker.grep_word()
	end, "Search Word Under Cursor")
	map("n", "<leader>ss", function()
		Snacks.picker.lsp_symbols()
	end, "Find Document Symbols")
	map("n", "<leader>sS", function()
		Snacks.picker.lsp_workspace_symbols()
	end, "Find Workspace Symbols")
	map("n", "<leader>sh", function()
		Snacks.picker.help()
	end, "Find Help")
	map("n", "<leader>sk", function()
		Snacks.picker.keymaps()
	end, "Find Keymaps")
	map("n", "<leader>sd", function()
		Snacks.picker.diagnostics()
	end, "Find Diagnostics")
	map("n", "<leader>su", function()
		vim.cmd.packadd("nvim.undotree")
		vim.cmd.Undotree()
	end, "Show Undo History")
	map("n", "<leader>sc", function()
		Snacks.picker.command_history()
	end, "Find Command History")
	map("n", "<leader>s.", function()
		Snacks.picker.resume()
	end, "Resume Last Search")
	map("n", "<leader>sr", "<cmd>GrugFar<cr>", "Search and Replace")

	-- Code actions are useful before and after LSP attachment; the calls are lazy.
	map("n", "<leader>ca", function()
		vim.lsp.buf.code_action()
	end, "Apply Code Action")
	map("n", "<leader>cr", function()
		vim.lsp.buf.rename()
	end, "Rename Symbol")
	map("n", "<leader>cf", function()
		require("lz.n").trigger_load("conform.nvim")
		require("conform").format({ async = true, lsp_format = "fallback" })
	end, "Format Buffer")
	map("n", "<leader>co", function()
		require("mayon.ui.workspace").action("structure")
	end, "Show Code Outline")
	map("n", "<leader>ci", function()
		vim.lsp.buf.incoming_calls()
	end, "Find Incoming Calls")
	map("n", "<leader>cO", function()
		vim.lsp.buf.outgoing_calls()
	end, "Find Outgoing Calls")
	map("n", "<leader>cl", function()
		require("lz.n").trigger_load("nvim-lint")
		require("lint").try_lint()
	end, "Run Linter")

	-- Trouble lists and UI controls.
	for _, spec in ipairs({
		{ "<leader>xx", "diagnostics toggle", "Toggle Workspace Diagnostics" },
		{ "<leader>xX", "diagnostics toggle filter.buf=0", "Toggle Buffer Diagnostics" },
		{ "<leader>xq", "qflist toggle", "Toggle Quickfix List" },
		{ "<leader>xl", "loclist toggle", "Toggle Location List" },
	}) do
		map("n", spec[1], "<cmd>Trouble " .. spec[2] .. "<cr>", spec[3])
	end
	map("n", "<leader>xw", function()
		vim.lsp.buf.workspace_diagnostics()
	end, "Collect Project Diagnostics")
	map("n", "<leader>ui", function()
		vim.cmd("EditorStatus")
	end, "Show Editor Status")
	vim.api.nvim_create_user_command("EditorStatus", function()
		local ai = require("mayon.features.ai_completion")
		local clients = vim.tbl_map(function(c)
			return c.name
		end, vim.lsp.get_clients({ bufnr = 0 }))
		vim.notify(
			"LSP: "
				.. (#clients > 0 and table.concat(clients, ", ") or "none")
				.. "\nAI: "
				.. ai.provider
				.. "\nGit: "
				.. ((vim.b.gitsigns_status_dict or {}).head or "none"),
			vim.log.levels.INFO,
			{ title = "Editor Status" }
		)
	end, { desc = "Show LSP, Git and AI status" })
	map("n", "<leader>uw", toggle_option("wrap", "自动折行"), "Toggle Line Wrap")
	map("n", "<leader>us", toggle_option("spell", "拼写检查"), "Toggle Spell Check")
	map("n", "<leader>uh", function()
		vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = 0 }), { bufnr = 0 })
	end, "Toggle Inlay Hints")
	map("n", "<leader>uz", function()
		Snacks.zen()
	end, "Toggle Zen Mode")
	map("n", "<leader>uf", function()
		vim.g.disable_autoformat = not vim.g.disable_autoformat
		vim.notify(vim.g.disable_autoformat and "保存时格式化已关闭" or "保存时格式化已开启")
	end, "Toggle Format on Save")
	map("n", "<leader>ud", function()
		Snacks.toggle.diagnostics():toggle()
	end, "Toggle Diagnostics")
	map("n", "<leader>un", toggle_option("relativenumber", "相对行号"), "Toggle Relative Numbers")
	map("n", "<leader>ua", function()
		require("mayon.features.ai_completion").cycle()
	end, "Cycle AI Completion")
	map("n", "<leader>au", function()
		require("mayon.features.ai_completion").cycle()
	end, "Cycle AI Completion")
	map("n", "<leader>tt", terminal("float"), "Open Floating Terminal")
	map("n", "<leader>tv", function()
		vim.cmd("botright vsplit")
		vim.cmd.terminal()
		vim.cmd.startinsert()
	end, "Open Split Terminal")
	map("n", "<leader>th", terminal("bottom"), "Open Bottom Terminal")
	map("n", "<leader>pp", function()
		Snacks.picker.projects()
	end, "Pick Project")
	map("n", "<leader>gg", function()
		Snacks.lazygit()
	end, "Open Lazygit")

	-- Diagnostics, Git hunks, TODOs and quickfix navigation.
	map("n", "[d", function()
		vim.diagnostic.jump({ count = -1, float = true })
	end, "Jump to Prev Diagnostic")
	map("n", "]d", function()
		vim.diagnostic.jump({ count = 1, float = true })
	end, "Jump to Next Diagnostic")
	map("n", "[q", "<cmd>cprev<cr>", "Jump to Prev Quickfix")
	map("n", "]q", "<cmd>cnext<cr>", "Jump to Next Quickfix")
	vim.keymap.set("n", "gx", function()
		require("mayon.features.urls").gx()
	end, { desc = "Open Link Under Cursor" })
	vim.keymap.set("x", "gx", function()
		require("mayon.features.urls").gx_visual()
	end, { desc = "Open Link from Selection" })

	vim.api.nvim_create_user_command("ImagePreview", function(args)
		if args.args ~= "" then
			vim.cmd.edit(vim.fn.fnameescape(vim.fn.expand(args.args)))
		else
			Snacks.image.hover()
		end
	end, { nargs = "?", complete = "file", desc = "Preview Image or Math" })
	map("n", "<Esc>", "<cmd>nohlsearch<cr>", "Clear Search Highlight")
end

return M
