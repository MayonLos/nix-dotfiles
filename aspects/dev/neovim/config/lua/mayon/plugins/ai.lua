local border = require("mayon.util").border

vim.api.nvim_create_user_command("AICompletion", function(args)
	local completion = require("mayon.features.ai_completion")
	if args.args == "" then
		completion.cycle()
	else
		completion.set(args.args)
	end
end, {
	nargs = "?",
	complete = function()
		return { "copilot", "deepseek", "off" }
	end,
	desc = "Cycle AI Completion",
})

local function prompt(alias, description, instruction)
	return {
		interaction = "chat",
		description = description,
		opts = { alias = alias, is_slash_cmd = true, auto_submit = false },
		prompts = {
			{
				role = "user",
				content = function(context)
					if context.is_visual then
						local code =
							require("codecompanion.helpers.code").get_code(context.start_line, context.end_line)
						return instruction .. "\n\n```" .. context.filetype .. "\n" .. code .. "\n```\n#{diagnostics}"
					end
					return instruction .. "\n\n#{buffer} #{diagnostics}"
				end,
			},
		},
	}
end
local function companion()
	require("mayon.config.loader").pack("codecompanion-history.nvim")
	require("mayon.config.loader").pack("mini.diff")
	require("mayon.ui.ai_panels").setup()
	require("codecompanion").setup({
		adapters = {
			acp = {
				-- Upstream presets (codex, claude_code, gemini_cli, ...) have no installed binary.
				opts = { show_presets = false },
			},
		},
		interactions = {
			chat = {
				adapter = "deepseek",
				keymaps = { regenerate = { modes = { n = "<localleader>r" } } },
				roles = {
					user = "YOU",
					llm = function(adapter)
						return ((adapter.formatted_name or adapter.name or "DeepSeek"):upper())
					end,
				},
				opts = { completion_provider = "default" },
			},
			inline = { adapter = "deepseek" },
			cmd = { adapter = "deepseek" },
		},
		display = {
			chat = {
				window = {
					border = border,
					-- Resolve geometry at every open, including after a resize. A
					-- focused float keeps chat usable without narrowing the document.
					layout = "float",
					position = "right",
					width = function()
						return math.min(100, math.floor(vim.o.columns * 0.88))
					end,
					opts = {
						number = false,
						relativenumber = false,
						signcolumn = "no",
						foldcolumn = "0",
						winhighlight = "Normal:NormalFloat,EndOfBuffer:NormalFloat",
					},
				},
				show_settings = false,
				start_in_insert_mode = false,
				intro_message = "❯ 继续提问 · Ctrl-S 发送",
				separator = "",
				show_header_separator = false,
			},
		},
		opts = { language = "Chinese" },
		prompt_library = {
			["解释报错"] = prompt(
				"errors",
				"用中文解释报错并给出最小修复",
				"请用中文解释诊断的根因，结合当前文件给出最小修复与验证步骤。"
			),
			["为选区写测试"] = {
				interaction = "chat",
				description = "为选区编写测试（中文说明）",
				opts = { alias = "tests", is_slash_cmd = true, auto_submit = false, modes = { "v" } },
				prompts = {
					{
						role = "user",
						content = function(context)
							local code =
								require("codecompanion.helpers.code").get_code(context.start_line, context.end_line)
							return "请为以下代码编写正常、边界与失败用例，复用项目现有测试框架，用中文解释覆盖范围：\n```"
								.. context.filetype
								.. "\n"
								.. code
								.. "\n```"
						end,
					},
				},
			},
			["生成提交信息"] = {
				interaction = "chat",
				description = "根据 Git diff 起草中文提交信息",
				opts = { alias = "commit", is_slash_cmd = true, auto_submit = false },
				prompts = {
					{
						role = "user",
						content = function()
							local result = vim.system({ "git", "diff", "--no-ext-diff", "--cached" }, { text = true })
								:wait()
							if result.code == 0 and result.stdout == "" then
								result = vim.system({ "git", "diff", "--no-ext-diff" }, { text = true }):wait()
							end
							return "请根据以下 diff 起草简洁中文提交信息（只起草）：\n```diff\n"
								.. (result.stdout or "")
								.. "\n```"
						end,
					},
				},
			},
			["中文重构"] = prompt(
				"refactor",
				"保持行为的重构建议",
				"请重构所选代码（无选区时参考当前文件），保持行为不变，用中文解释理由与风险。"
			),
			["添加注释"] = prompt(
				"comments",
				"为代码添加必要的中文注释",
				"请为所选代码（无选区时参考当前文件）添加必要的中文注释，重点解释意图与约束，避免复述实现。"
			),
		},
		extensions = {
			history = {
				enabled = true,
				opts = {
					auto_save = true,
					auto_generate_title = false,
					continue_last_chat = false,
					keymap = "gh",
					save_chat_keymap = "<localleader>h",
				},
			},
		},
	})
	require("mayon.features.cc_minidiff").setup()
	require("mayon.features.cc_inline_indicator").setup()
end
local function cc_prompt(name)
	if not require("mayon.features.ai_completion").require_deepseek_key() then
		return false
	end
	require("lz.n").trigger_load("codecompanion.nvim")
	require("codecompanion").prompt(name)
	return true
end
local function map(lhs, rhs, desc, mode)
	return { lhs, rhs, desc = desc, mode = mode or "n" }
end
return {
	{
		"codecompanion.nvim",
		cmd = { "CodeCompanion", "CodeCompanionChat", "CodeCompanionActions", "CodeCompanionCmd" },
		keys = {
			map("<leader>ad", function()
				if require("mayon.features.ai_completion").require_deepseek_key() then
					require("lz.n").trigger_load("codecompanion.nvim")
					vim.cmd("CodeCompanionChat Toggle")
				end
			end, "Open DeepSeek Chat", { "n", "v" }),
			map("<leader>ai", function()
				if require("mayon.features.ai_completion").require_deepseek_key() then
					require("lz.n").trigger_load("codecompanion.nvim")
					vim.cmd.CodeCompanion()
				end
			end, "Review Inline Edit", { "n", "v" }),
			map("<leader>ae", function()
				cc_prompt("解释报错")
			end, "Explain Diagnostics"),
			map("<leader>at", function()
				cc_prompt("为选区写测试")
			end, "Write Tests for Selection", "v"),
			map("<leader>am", function()
				cc_prompt("生成提交信息")
			end, "Draft Commit Message"),
			map("<leader>ap", "<cmd>CodeCompanionActions<cr>", "Browse Prompt Library", { "n", "v" }),
			map("<leader>ah", function()
				require("codecompanion").extensions.history.browse_chats()
			end, "Browse Chat History"),
		},
		after = companion,
	},
	{
		"minuet-ai.nvim",
		cmd = "Minuet",
		after = function()
			require("mayon.features.ai_completion").minuet_setup()
		end,
	},
}
