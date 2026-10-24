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

local function close_smart()
	if #vim.api.nvim_list_wins() > 1 then
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
				border = "rounded",
			},
		})
	end
end

function M.setup()
	local Snacks = require("snacks")
	vim.g.mapleader = " "
	vim.g.maplocalleader = ","

	-- Top-level navigation and safe file actions.
	map("n", "<leader><leader>", function()
		Snacks.picker.smart()
	end, "智能查找文件")
	map("n", "<leader>/", function()
		Snacks.picker.grep()
	end, "全文搜索")
	map("n", "<leader>,", function()
		Snacks.picker.buffers()
	end, "切换缓冲区")
	map("n", "<leader>.", function()
		require("mayon.features.scratch").scratch()
	end, "打开草稿")
	map("n", "<leader>w", "<cmd>write<cr>", "保存文件")
	map("n", "<leader>qq", close_smart, "关闭窗口或缓冲区")
	map("n", "<leader>qr", "<cmd>restart<cr>", "重启 Neovim 并保留界面")
	map("n", "<leader>e", function()
		Snacks.explorer()
	end, "打开文件树")
	map("n", "<leader>fn", "<cmd>enew<cr>", "新建文件")
	map("n", "<leader>fD", delete_to_trash, "移入回收站")
	map("n", "<leader>fc", function()
		Snacks.picker.files({ cwd = vim.env.NVIM_CONFIG_DIR or vim.fn.stdpath("config") })
	end, "打开 Neovim 配置")
	map("n", "<leader>fR", function()
		Snacks.rename.rename_file()
	end, "安全重命名文件")
	map("n", "-", function()
		vim.cmd("Oil")
	end, "编辑父目录")

	-- Search, symbols and picker history.
	map("n", "<leader>sw", function()
		Snacks.picker.grep_word()
	end, "搜索光标下的词")
	map("n", "<leader>ss", function()
		Snacks.picker.lsp_symbols()
	end, "搜索文档符号")
	map("n", "<leader>sS", function()
		Snacks.picker.lsp_workspace_symbols()
	end, "搜索工作区符号")
	map("n", "<leader>sh", function()
		Snacks.picker.help()
	end, "搜索帮助")
	map("n", "<leader>sk", function()
		Snacks.picker.keymaps()
	end, "搜索快捷键")
	map("n", "<leader>sd", function()
		Snacks.picker.diagnostics()
	end, "搜索诊断")
	map("n", "<leader>su", function()
		vim.cmd.packadd("nvim.undotree")
		vim.cmd.Undotree()
	end, "查看撤销历史")
	map("n", "<leader>sc", function()
		Snacks.picker.command_history()
	end, "搜索命令历史")
	map("n", "<leader>s.", function()
		Snacks.picker.resume()
	end, "恢复上次搜索")
	map("n", "<leader>sr", "<cmd>GrugFar<cr>", "搜索并替换")

	-- Code actions are useful before and after LSP attachment; the calls are lazy.
	map("n", "<leader>ca", function()
		vim.lsp.buf.code_action()
	end, "执行代码动作")
	map("n", "<leader>cr", function()
		vim.lsp.buf.rename()
	end, "重命名符号")
	map("n", "<leader>cf", function()
		require("lz.n").trigger_load("conform.nvim")
		require("conform").format({ async = true, lsp_format = "fallback" })
	end, "格式化当前文件")
	map("n", "<leader>co", function()
		require("lz.n").trigger_load("trouble.nvim")
		vim.cmd("Trouble symbols toggle focus=false")
	end, "打开代码大纲")
	map("n", "<leader>ci", function()
		vim.lsp.buf.incoming_calls()
	end, "查看调用者")
	map("n", "<leader>cO", function()
		vim.lsp.buf.outgoing_calls()
	end, "查看被调用项")
	map("n", "<leader>cl", function()
		require("lz.n").trigger_load("nvim-lint")
		require("lint").try_lint()
	end, "运行代码检查")

	-- Trouble lists and UI controls.
	for _, spec in ipairs({
		{ "<leader>xx", "diagnostics toggle", "切换工作区诊断列表" },
		{ "<leader>xX", "diagnostics toggle filter.buf=0", "切换当前文件诊断列表" },
		{ "<leader>xq", "qflist toggle", "切换快速修复列表" },
		{ "<leader>xl", "loclist toggle", "切换位置列表" },
	}) do
		map("n", spec[1], "<cmd>Trouble " .. spec[2] .. "<cr>", spec[3])
	end
	map("n", "<leader>xw", function()
		vim.lsp.buf.workspace_diagnostics()
	end, "收集工作区诊断")
	map("n", "<leader>uw", toggle_option("wrap", "自动折行"), "切换自动折行")
	map("n", "<leader>us", toggle_option("spell", "拼写检查"), "切换拼写检查")
	map("n", "<leader>uh", function()
		vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = 0 }), { bufnr = 0 })
	end, "切换行内提示")
	map("n", "<leader>uz", function()
		Snacks.zen()
	end, "切换专注模式")
	map("n", "<leader>uf", function()
		vim.g.disable_autoformat = not vim.g.disable_autoformat
		vim.notify(vim.g.disable_autoformat and "保存时格式化已关闭" or "保存时格式化已开启")
	end, "切换保存时格式化")
	map("n", "<leader>ud", function()
		Snacks.toggle.diagnostics():toggle()
	end, "切换诊断显示")
	map("n", "<leader>un", toggle_option("relativenumber", "相对行号"), "切换相对行号")
	map("n", "<leader>ua", function()
		require("mayon.features.ai_completion").cycle()
	end, "切换 AI 补全提供者")
	map("n", "<leader>au", function()
		require("mayon.features.ai_completion").cycle()
	end, "切换 AI 补全提供者")
	map("n", "<leader>tt", terminal("float"), "打开浮动终端")
	map("n", "<leader>tv", function()
		vim.cmd("botright vsplit")
		vim.cmd.terminal()
		vim.cmd.startinsert()
	end, "打开竖分终端")
	map("n", "<leader>th", terminal("bottom"), "打开底部终端")
	map("n", "<leader>pp", function()
		Snacks.picker.projects()
	end, "切换项目")
	map("n", "<leader>gg", function()
		Snacks.lazygit()
	end, "打开 Lazygit")
	map("i", "<A-]>", function()
		require("mayon.features.ai_completion").step("next")
	end, "下一个 AI 建议")
	map("i", "<A-[>", function()
		require("mayon.features.ai_completion").step("prev")
	end, "上一个 AI 建议")

	-- Diagnostics, Git hunks, TODOs and quickfix navigation.
	map("n", "[d", function()
		vim.diagnostic.jump({ count = -1, float = true })
	end, "上一个诊断")
	map("n", "]d", function()
		vim.diagnostic.jump({ count = 1, float = true })
	end, "下一个诊断")
	map("n", "[q", "<cmd>cprev<cr>", "上一个快速修复项")
	map("n", "]q", "<cmd>cnext<cr>", "下一个快速修复项")
	vim.keymap.set("n", "gx", function()
		require("mayon.features.urls").gx()
	end, { desc = "打开光标下链接" })
	vim.keymap.set("x", "gx", function()
		require("mayon.features.urls").gx_visual()
	end, { desc = "打开选区中的链接" })

	vim.api.nvim_create_user_command("ImagePreview", function(args)
		if args.args ~= "" then
			vim.cmd.edit(vim.fn.fnameescape(vim.fn.expand(args.args)))
		else
			Snacks.image.hover()
		end
	end, { nargs = "?", complete = "file", desc = "预览图片或公式" })
	vim.api.nvim_create_autocmd("LspAttach", {
		group = vim.api.nvim_create_augroup("MayonKeymapDescriptions", { clear = true }),
		callback = function(event)
			local bufnr = event.buf
			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(bufnr) then
					return
				end
				vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, {
					buffer = bufnr,
					desc = "执行代码动作",
					silent = true,
				})
				vim.keymap.set("n", "<leader>cr", vim.lsp.buf.rename, {
					buffer = bufnr,
					desc = "重命名符号",
					silent = true,
				})
				vim.keymap.set("n", "[d", function()
					vim.diagnostic.jump({ count = -1, float = true })
				end, { desc = "上一个诊断", silent = true })
				vim.keymap.set("n", "]d", function()
					vim.diagnostic.jump({ count = 1, float = true })
				end, { desc = "下一个诊断", silent = true })
			end)
		end,
	})
	map("n", "<Esc>", "<cmd>nohlsearch<cr>", "清除搜索高亮")
end

return M
