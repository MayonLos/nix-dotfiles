local M = {}

local function setup()
	require("gitsigns").setup({
		signs = {
			add = { text = "▎" },
			change = { text = "▎" },
			delete = { text = "▎" },
			topdelete = { text = "▎" },
			changedelete = { text = "▎" },
			untracked = { text = "▎" },
		},
		current_line_blame = false,
	})
	local function map(mode, lhs, callback, desc)
		vim.keymap.set(mode, lhs, callback, { desc = desc })
	end
	local gs = require("gitsigns")
	map("n", "]h", function()
		gs.nav_hunk("next")
	end, "Jump to Next Hunk")
	map("n", "[h", function()
		gs.nav_hunk("prev")
	end, "Jump to Prev Hunk")
	map("n", "<leader>gs", function()
		gs.stage_hunk()
	end, "Stage or Unstage Hunk")
	map("v", "<leader>gs", function()
		gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
	end, "Stage Selection")
	map("n", "<leader>gr", function()
		gs.reset_hunk()
	end, "Reset Hunk")
	map("v", "<leader>gr", function()
		gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
	end, "Reset Selection")
	map("n", "<leader>gS", function()
		gs.stage_buffer()
	end, "Stage Buffer")
	map("n", "<leader>gR", function()
		gs.reset_buffer()
	end, "Reset Buffer")
	map("n", "<leader>gp", function()
		gs.preview_hunk_inline()
	end, "Preview Hunk")
	map("n", "<leader>gb", function()
		gs.toggle_current_line_blame()
	end, "Toggle Line Blame")
	map("n", "<leader>gq", function()
		gs.setqflist("all")
	end, "List All Hunks")
	vim.keymap.set("n", "<leader>gd", "<cmd>CodeDiff<cr>", { desc = "Review Workspace Diff" })
	vim.keymap.set("n", "<leader>gf", "<cmd>CodeDiff history %<cr>", { desc = "Show File History" })
	vim.keymap.set("n", "<leader>gD", function()
		vim.ui.input({ prompt = "比较工作区与提交或分支：", default = "HEAD~1" }, function(revision)
			if revision and revision ~= "" then
				vim.cmd({ cmd = "CodeDiff", args = { revision } })
			end
		end)
	end, { desc = "Compare with Revision" })
	vim.keymap.set("n", "<leader>gC", function()
		local file = vim.api.nvim_buf_get_name(0)
		if file == "" then
			vim.notify("冲突审阅需要当前文件", vim.log.levels.WARN)
			return
		end
		vim.cmd({ cmd = "CodeDiff", args = { "merge", file } })
	end, { desc = "Review File Conflicts" })
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
	end, { desc = "Compare Directories" })
	vim.keymap.set({ "n", "v" }, "<leader>gB", function()
		require("snacks").gitbrowse()
	end, { desc = "Open File on Remote", silent = true })
end

return {
	{ "gitsigns.nvim", event = { "BufReadPost", "BufNewFile" }, after = setup },
	{
		"codediff.nvim",
		cmd = { "CodeDiff" },
		after = function()
			local palette = require("mayon.generated").palette
			local blend = require("mayon.ui.theme").blend
			local line_insert = blend(palette.green, palette.bg, 0.12)
			local line_delete = blend(palette.red, palette.bg, 0.12)
			local char_insert = blend(palette.green, palette.bg, 0.18)
			local char_delete = blend(palette.red, palette.bg, 0.18)
			-- The Nix package ships libvscode_diff.so (unversioned). Skip upstream's
			-- mutable auto-installer and let codediff's loader use its local fallback.
			vim.env.VSCODE_DIFF_NO_AUTO_INSTALL = "1"
			require("codediff").setup({
				highlights = {
					line_insert = line_insert,
					line_delete = line_delete,
					char_insert = char_insert,
					char_delete = char_delete,
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
			-- codediff resolves configured colors to backgrounds only. Restore its
			-- foregrounds after plugin initialization and after its ColorScheme hook.
			require("mayon.ui.theme").refresh()
			vim.api.nvim_create_autocmd("ColorScheme", {
				group = vim.api.nvim_create_augroup("MayonCodeDiffTheme", { clear = true }),
				callback = function()
					require("mayon.ui.theme").refresh()
				end,
			})
		end,
	},
	{
		"neogit",
		cmd = "Neogit",
		after = function()
			require("neogit").setup({
				kind = "floating",
				commit_editor = { kind = "floating" },
				log_view = { kind = "floating" },
				popup = { kind = "floating" },
			})
		end,
	},
}
