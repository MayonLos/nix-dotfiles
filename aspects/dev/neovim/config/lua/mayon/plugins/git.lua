local M = {}

local function setup()
	require("gitsigns").setup({})
	local function map(mode, lhs, callback, desc)
		vim.keymap.set(mode, lhs, callback, { desc = desc })
	end
	local gs = require("gitsigns")
	map("n", "]h", function()
		gs.nav_hunk("next")
	end, "下一个 Git 修改块")
	map("n", "[h", function()
		gs.nav_hunk("prev")
	end, "上一个 Git 修改块")
	map("n", "<leader>gs", function()
		gs.stage_hunk()
	end, "暂存或取消暂存修改块")
	map("v", "<leader>gs", function()
		gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
	end, "暂存选区")
	map("n", "<leader>gr", function()
		gs.reset_hunk()
	end, "还原修改块")
	map("v", "<leader>gr", function()
		gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
	end, "还原选区")
	map("n", "<leader>gS", function()
		gs.stage_buffer()
	end, "暂存整个文件")
	map("n", "<leader>gR", function()
		gs.reset_buffer()
	end, "还原整个文件")
	map("n", "<leader>gp", function()
		gs.preview_hunk_inline()
	end, "预览修改块")
	map("n", "<leader>gb", function()
		gs.blame_line({ full = true })
	end, "查看当前行责任人")
	map("n", "<leader>gq", function()
		gs.setqflist("all")
	end, "所有修改块加入快速修复列表")
	vim.keymap.set("n", "<leader>gd", "<cmd>CodeDiff<cr>", { desc = "审阅工作区 Git 改动" })
	vim.keymap.set("n", "<leader>gf", "<cmd>CodeDiff history %<cr>", { desc = "查看当前文件历史" })
	vim.keymap.set("n", "<leader>gD", function()
		vim.ui.input({ prompt = "比较工作区与提交或分支：", default = "HEAD~1" }, function(revision)
			if revision and revision ~= "" then
				vim.cmd({ cmd = "CodeDiff", args = { revision } })
			end
		end)
	end, { desc = "与提交或分支比较" })
	vim.keymap.set("n", "<leader>gC", function()
		local file = vim.api.nvim_buf_get_name(0)
		if file == "" then
			vim.notify("冲突审阅需要当前文件", vim.log.levels.WARN)
			return
		end
		vim.cmd({ cmd = "CodeDiff", args = { "merge", file } })
	end, { desc = "打开当前文件冲突审阅" })
	vim.keymap.set("n", "<leader>gT", function()
		local left = vim.fn.getcwd()
		vim.ui.input({ prompt = "目录比较：左侧目录：", default = left, completion = "dir" }, function(first)
			if not first or first == "" then
				return
			end
			vim.ui.input({ prompt = "目录比较：右侧目录：", completion = "dir" }, function(second)
				if not second or second == "" then
					return
				end
				vim.cmd.packadd("nvim.difftool")
				vim.cmd({ cmd = "DiffTool", args = { first, second } })
			end)
		end)
	end, { desc = "比较两个目录（Neovim 原生）" })
	vim.keymap.set({ "n", "v" }, "<leader>gB", function()
		require("snacks").gitbrowse()
	end, { desc = "在远程仓库中打开", silent = true })
end

return {
	{ "gitsigns.nvim", event = { "BufReadPost", "BufNewFile" }, after = setup },
	{
		"codediff.nvim",
		cmd = { "CodeDiff" },
		after = function()
			local palette = require("mayon.generated").palette
			vim.api.nvim_set_hl(0, "CodeDiffCharInsert", { fg = palette.green, bg = palette.selection, bold = true })
			vim.api.nvim_set_hl(0, "CodeDiffCharDelete", { fg = palette.red, bg = palette.surface, bold = true })
			-- The Nix package ships libvscode_diff.so (unversioned). Skip upstream's
			-- mutable auto-installer and let codediff's loader use its local fallback.
			vim.env.VSCODE_DIFF_NO_AUTO_INSTALL = "1"
			require("codediff").setup({
				highlights = {
					line_insert = "DiffAdd",
					line_delete = "DiffDelete",
					char_insert = "CodeDiffCharInsert",
					char_delete = "CodeDiffCharDelete",
					conflict_sign = "DiagnosticSignWarn",
					conflict_sign_resolved = "Comment",
					conflict_sign_accepted = "DiagnosticSignOk",
					conflict_sign_rejected = "DiagnosticSignError",
				},
				diff = { layout = "side-by-side" },
				explorer = {
					position = "left",
					width = 30,
					view_mode = "tree",
					icons = { folder_closed = "", folder_open = "" },
				},
			})
		end,
	},
}
