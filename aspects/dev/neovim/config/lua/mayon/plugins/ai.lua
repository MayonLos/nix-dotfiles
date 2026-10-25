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
local function acp_path(name)
	local tools = require("mayon.generated").tools
	local path = name == "codex" and (vim.env.NVIM_CODEX_ACP or tools.codex_acp)
		or (vim.env.NVIM_CLAUDE_ACP or tools.claude_acp)
	assert(
		path and path:sub(1, 1) == "/" and vim.fn.executable(path) == 1,
		"ACP 可执行路径不可用：请启用 ai-workbench 并重新登录会话"
	)
	return path
end
local function notify_cli_missing(name, label)
	if vim.fn.executable(name) == 1 then
		return false
	end
	vim.notify(
		label .. " 命令不在 PATH 中；请先安装或启用对应环境",
		vim.log.levels.WARN,
		{ title = "AI 助手" }
	)
	return true
end
local function companion()
	require("mayon.config.loader").pack("codecompanion-history.nvim")
	require("mayon.config.loader").pack("mini.diff")
	require("mayon.ui.ai_panels").setup()
	require("codecompanion").setup({
		adapters = {
			acp = {
				codex = function()
					return require("codecompanion.adapters").extend("codex", {
						commands = { default = { acp_path("codex") } },
						defaults = { auth_method = "chatgpt" },
					})
				end,
				claude_code = function()
					return require("codecompanion.adapters").extend("claude_code", {
						commands = { default = { acp_path("claude") }, yolo = { acp_path("claude"), "--yolo" } },
					})
				end,
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
					border = "rounded",
					layout = vim.o.columns < 120 and "float" or "vertical",
					position = "right",
					width = vim.o.columns < 120 and 0.88 or 0.42,
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
local function claude()
	require("mayon.ui.ai_panels").setup()
	require("claudecode").setup({
		auto_start = true,
		track_selection = true,
		focus_after_send = false,
		terminal = {
			provider = "snacks",
			split_side = "right",
			split_width_percentage = 0.36,
			snacks_win_opts = {
				position = vim.o.columns < 120 and "float" or "right",
				border = "rounded",
				title = " Claude Code ",
				bo = { filetype = "claudecode" },
				wo = { winhighlight = "Normal:NormalFloat,WinBar:FloatTitle" },
			},
		},
		diff_opts = {
			layout = "vertical",
			open_in_new_tab = true,
			hide_terminal_in_new_tab = true,
			keep_terminal_focus = false,
		},
	})
	-- The pinned plugin has no public connection User event. Poll only after
	-- loading Claude, and redraw only on a connection transition.
	local connected = require("claudecode").is_claude_connected()
	local timer = assert(vim.uv.new_timer())
	timer:start(
		500,
		500,
		vim.schedule_wrap(function()
			local current = require("claudecode").is_claude_connected()
			if current ~= connected then
				connected = current
				vim.api.nvim_exec_autocmds("User", { pattern = "MayonAIStatus", modeline = false })
				vim.cmd.redrawstatus()
			end
		end)
	)
	vim.api.nvim_create_autocmd("VimLeavePre", {
		once = true,
		callback = function()
			timer:stop()
			timer:close()
		end,
	})

	vim.api.nvim_create_autocmd({ "BufWinEnter", "WinEnter" }, {
		group = vim.api.nvim_create_augroup("MayonClaudeReview", { clear = true }),
		callback = function(ev)
			vim.schedule(function()
				if not vim.api.nvim_buf_is_valid(ev.buf) or not vim.b[ev.buf].claudecode_diff_tab_name then
					return
				end
				vim.keymap.set(
					"n",
					"<localleader>a",
					"<cmd>ClaudeCodeDiffAccept<cr>",
					{ buffer = ev.buf, desc = "Accept Claude File Changes" }
				)
				vim.keymap.set(
					"n",
					"<localleader>r",
					"<cmd>ClaudeCodeDiffDeny<cr>",
					{ buffer = ev.buf, desc = "Reject Claude File Changes" }
				)
				require("mayon.ui.ai_panels").style_diff(ev.buf)
			end)
		end,
	})
end
local function sidekick()
	require("mayon.ui.ai_panels").setup()
	require("sidekick").setup({
		nes = {
			enabled = function(buf)
				return require("mayon.features.ai_completion").provider == "copilot"
					and require("mayon.features.ai_completion").allowed(buf)
			end,
		},
		cli = {
			mux = { enabled = false },
			win = {
				layout = vim.o.columns < 120 and "float" or "right",
				split = { width = 60 },
				nav = function(dir)
					local name = ({ h = "left", j = "down", k = "up", l = "right" })[dir]
					require("lz.n").trigger_load("smart-splits.nvim")
					require("smart-splits")["move_cursor_" .. name]()
				end,
			},
		},
	})
	-- 2.3.0 deep-merges defaults and has no disable flag per tool. Replace the
	-- public tools table after setup so Claude has exactly one terminal owner.
	require("sidekick.config").cli.tools = { codex = { cmd = { "codex" } }, grok = { cmd = { "grok" } } }
end
local function cc_prompt(name)
	if not require("mayon.features.ai_completion").require_deepseek_key() then
		return false
	end
	require("lz.n").trigger_load("codecompanion.nvim")
	require("codecompanion").prompt(name)
	return true
end
local function send(message)
	if vim.fn.executable("codex") ~= 1 and vim.fn.executable("grok") ~= 1 then
		vim.notify(
			"未找到 Codex 或 Grok 命令；请先将 CLI 加入 PATH",
			vim.log.levels.WARN,
			{ title = "Sidekick" }
		)
		return false
	end
	local ok, err = pcall(function()
		require("lz.n").trigger_load("sidekick.nvim")
		require("sidekick.cli").send({ msg = message, focus = false })
	end)
	if not ok then
		vim.notify("无法发送到 Sidekick：" .. tostring(err), vim.log.levels.WARN, { title = "Sidekick" })
	end
	return ok
end
local function toggle_cli(name)
	if vim.fn.executable(name) ~= 1 then
		vim.notify(name .. " 不在 PATH 中；请先安装或启用对应开发环境", vim.log.levels.WARN, {
			title = "Sidekick",
		})
		return false
	end
	local ok, err = pcall(function()
		require("lz.n").trigger_load("sidekick.nvim")
		require("sidekick.cli").toggle({ name = name, focus = true })
	end)
	if not ok then
		vim.notify("无法启动 " .. name .. "：" .. tostring(err), vim.log.levels.WARN, { title = "Sidekick" })
	end
	return ok
end
local function map(lhs, rhs, desc, mode)
	return { lhs, rhs, desc = desc, mode = mode or "n" }
end
return {
	{
		"claudecode.nvim",
		cmd = {
			"ClaudeCode",
			"ClaudeCodeStart",
			"ClaudeCodeStop",
			"ClaudeCodeSend",
			"ClaudeCodeAdd",
			"ClaudeCodeDiffAccept",
			"ClaudeCodeDiffDeny",
		},
		keys = {
			map("<leader>ac", function()
				if not notify_cli_missing("claude", "Claude Code") then
					vim.cmd("ClaudeCode")
				end
			end, "Toggle Claude Code"),
			map("<leader>as", function()
				if not notify_cli_missing("claude", "Claude Code") then
					vim.cmd("ClaudeCodeSend")
				end
			end, "Send Selection to Claude", "v"),
			map("<leader>aA", "<cmd>ClaudeCodeDiffAccept<cr>", "Accept Claude Changes"),
			map("<leader>aD", "<cmd>ClaudeCodeDiffDeny<cr>", "Reject Claude Changes"),
		},
		after = claude,
	},
	{
		"sidekick.nvim",
		cmd = "Sidekick",
		keys = {
			map("<leader>ax", function()
				toggle_cli("codex")
			end, "Toggle Codex CLI"),
			map("<leader>ag", function()
				toggle_cli("grok")
			end, "Toggle Grok CLI"),
			map("<leader>af", function()
				send("{file}")
			end, "Send File to AI CLI"),
			map("<leader>av", function()
				send("{selection}")
			end, "Send Selection to AI CLI", "v"),
			map("<leader>aE", function()
				send("{diagnostics}")
			end, "Send Diagnostics to AI CLI"),
			map("<leader>aG", function()
				local result = vim.system({ "git", "diff", "--no-ext-diff" }, { text = true }):wait()
				if result.code == 0 then
					send("请审阅以下 Git diff：\n" .. result.stdout)
				end
			end, "Send Git Diff to AI CLI"),
			map("<Tab>", function()
				if not require("sidekick").nes_jump_or_apply() then
					vim.api.nvim_feedkeys(vim.keycode("<Tab>"), "n", false)
				end
			end, "Apply Next Copilot Edit"),
		},
		after = sidekick,
	},
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
