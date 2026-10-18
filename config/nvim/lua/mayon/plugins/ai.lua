local M = {}

local function visual_prompt(alias, description, prompt)
	return {
		interaction = "chat",
		description = description,
		opts = {
			is_slash_cmd = true,
			alias = alias,
			modes = { "v" },
			auto_submit = true,
			stop_context_insertion = true,
		},
		prompts = {
			{
				role = "user",
				content = function(context)
					local code = require("codecompanion.helpers.code").get_code(context.start_line, context.end_line)
					return string.format(prompt .. "\n\n```%s\n%s\n```", context.filetype, context.filetype, code)
				end,
			},
		},
	}
end

function M.setup()
	-- DeepSeek uses CodeCompanion's built-in adapter. The CLI agent names map
	-- directly to the installed codex, grok, and opencode executables.
	require("codecompanion").setup({
		interactions = {
			chat = {
				adapter = "deepseek",
				opts = { completion_provider = "blink" },
				keymaps = {
					send = { modes = { n = "<CR>", i = "<C-s>" } },
					regenerate = { modes = { n = "<leader>ar" } },
				},
			},
			inline = { adapter = "deepseek" },
			cmd = { adapter = "deepseek" },
			cli = {
				agent = "codex",
				agents = {
					codex = { cmd = "codex" },
					grok = { cmd = "grok" },
					opencode = { cmd = "opencode" },
				},
			},
		},
		display = {
			chat = {
				window = {
					layout = "vertical",
					position = "right",
					width = 0.42,
					opts = {
						number = false,
						relativenumber = false,
						signcolumn = "no",
						foldcolumn = "0",
						statuscolumn = "",
						cursorline = false,
						fillchars = "eob: ",
						winhighlight = "Normal:NormalFloat,EndOfBuffer:NormalFloat,SignColumn:NormalFloat",
					},
				},
				separator = "─",
				show_header_separator = false,
				show_settings = false,
				show_token_count = true,
				start_in_insert_mode = false,
				fold_context = true,
				fold_reasoning = true,
				icons = { chat_context = "󰈙 ", chat_fold = " " },
			},
		},
		opts = { language = "Chinese" },
		prompt_library = {
			["中文 Code Review"] = visual_prompt(
				"review",
				"用中文审查选中的代码",
				"请用中文审查以下 %s 代码，指出潜在 bug、可读性与性能问题，并给出改进建议："
			),
			["中文重构"] = visual_prompt(
				"refactor",
				"重构选中代码并用中文说明",
				"请重构以下 %s 代码：保持行为不变，提升可读性与健壮性。先用中文说明改了什么、为什么，再给出完整代码："
			),
			["实现+测试工作流"] = {
				interaction = "chat",
				description = "实现 → 写测试 → 跑测试并修复 (agentic)",
				opts = { is_workflow = true },
				prompts = {
					{
						{
							role = "user",
							opts = { auto_submit = false },
							content = "你是结对编程助手。请用 @{insert_edit_into_file} 直接修改文件来实现下面的需求；动手前先简要说明思路。需求：",
						},
					},
					{
						{
							role = "user",
							opts = { auto_submit = true },
							content = "现在为上面的实现编写单元测试，覆盖正常与边界情况，并用 @{insert_edit_into_file} 写入对应的测试文件。",
						},
					},
					{
						{
							role = "user",
							opts = { auto_submit = true },
							content = "用 @{run_command} 编译并运行测试。若有失败，分析原因、用 @{insert_edit_into_file} 修复后重新运行，直到全部通过。",
						},
					},
				},
			},
		},
		extensions = {
			-- Keep titles local: generating one would make an extra model request.
			history = {
				enabled = true,
				opts = {
					auto_save = true,
					auto_generate_title = false,
					continue_last_chat = false,
					keymap = "gh",
					save_chat_keymap = "<leader>as",
				},
			},
		},
	})

	require("mayon.plugins.cc_inline_indicator").setup()
	vim.api.nvim_create_autocmd("FileType", {
		group = vim.api.nvim_create_augroup("MayonCodeCompanionCli", { clear = true }),
		pattern = "codecompanion_cli",
		callback = function(args)
			vim.schedule(function()
				for _, win in ipairs(vim.fn.win_findbuf(args.buf)) do
					vim.wo[win].number = false
					vim.wo[win].relativenumber = false
					vim.wo[win].signcolumn = "no"
					vim.wo[win].foldcolumn = "0"
				end
			end)
		end,
	})

	local function map(mode, lhs, rhs, desc, opts)
		opts = opts or {}
		opts.desc = desc
		vim.keymap.set(mode, lhs, rhs, opts)
	end
	local nv = { "n", "v" }
	map(nv, "<leader>aa", "<cmd>CodeCompanionChat Toggle<cr>", "CodeCompanion: toggle chat")
	map(nv, "<leader>ap", "<cmd>CodeCompanionActions<cr>", "CodeCompanion: action palette")
	map("v", "<leader>av", "<cmd>CodeCompanionChat Add<cr>", "CodeCompanion: add selection to chat")
	map("n", "<leader>ai", "<cmd>CodeCompanion<cr>", "CodeCompanion: inline assistant")
	map("v", "<leader>ai", ":CodeCompanion<cr>", "CodeCompanion: inline assistant (selection)")
	map("n", "<leader>at", "<cmd>CodeCompanionCLI<cr>", "CodeCompanion: CLI (default agent)")
	map("n", "<leader>ah", function()
		require("codecompanion").extensions.history.browse_chats()
	end, "CodeCompanion: chat history")
	map(nv, "<leader>acp", function()
		require("codecompanion").cli({ prompt = true })
	end, "CLI agent: prompt (selection-aware)")
	map(nv, "<leader>aca", function()
		require("codecompanion").cli("#{this}", { focus = false })
	end, "CLI agent: add buffer/selection as context")
	map("n", "<leader>acd", function()
		require("codecompanion").cli("#{diagnostics} 请修复这些问题", { focus = false, submit = true })
	end, "CLI agent: fix LSP diagnostics")
	map("n", "<leader>act", function()
		require("codecompanion").cli(
			"#{terminal} 这是终端输出，请帮我修复",
			{ focus = false, submit = true }
		)
	end, "CLI agent: fix terminal output")
	map("n", "<leader>ax", ":CodeCompanionCmd ", "CodeCompanion: generate command", { silent = false })
	map("n", "<leader>aT", ":CodeCompanionCLI agent=", "CodeCompanion: CLI (pick agent)", { silent = false })
end

return M
