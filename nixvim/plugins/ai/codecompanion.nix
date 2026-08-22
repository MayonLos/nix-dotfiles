{ pkgs, ... }:
let
  mkVisualPrompt =
    {
      alias,
      description,
      prompt,
    }:
    {
      interaction = "chat";
      inherit description;
      opts = {
        is_slash_cmd = true;
        inherit alias;
        modes = [ "v" ];
        auto_submit = true;
        stop_context_insertion = true;
      };
      prompts = [
        {
          role = "user";
          content.__raw = ''
            function(context)
              local code = require("codecompanion.helpers.code").get_code(context.start_line, context.end_line)
              return string.format(
                "${prompt}\n\n```%s\n%s\n```",
                context.filetype,
                context.filetype,
                code
              )
            end
          '';
        }
      ];
    };
in
{
  plugins.codecompanion = {
    enable = true;

    lazyLoad.settings.cmd = [
      "CodeCompanion"
      "CodeCompanionChat"
      "CodeCompanionActions"
    ];
    settings = {
      interactions = {
        chat = {
          adapter = "copilot_acp";
          opts.completion_provider = "blink";
          keymaps.send.modes = {
            n = "<CR>";
            i = "<C-s>";
          };
        };

        inline.adapter = "deepseek";
        cmd.adapter = "deepseek";

        cli = {
          agent = "claude";
          agents = {
            claude.cmd = "claude";
            codex.cmd = "codex";
            copilot.cmd = "copilot";
            antigravity.cmd = "agy";
          };
        };
      };

      display.chat = {
        window = {
          layout = "vertical";
          position = "right";
          width = 0.42;
          opts = {
            number = false;
            relativenumber = false;
            signcolumn = "no";
            foldcolumn = "0";
            statuscolumn = "";
            cursorline = false;
            fillchars = "eob: ";
            winhighlight = "Normal:NormalFloat,EndOfBuffer:NormalFloat,SignColumn:NormalFloat";
          };
        };
        separator = "─";
        show_header_separator = false;
        show_settings = false;
        show_token_count = true;
        start_in_insert_mode = false;
        fold_context = true;
        fold_reasoning = true;
        icons = {
          chat_context = "󰈙 ";
          chat_fold = " ";
        };
      };

      opts.language = "Chinese";

      prompt_library = {
        "中文 Code Review" = mkVisualPrompt {
          alias = "review";
          description = "用中文审查选中的代码";
          prompt = "请用中文审查以下 %s 代码，指出潜在 bug、可读性与性能问题，并给出改进建议：";
        };

        "中文重构" = mkVisualPrompt {
          alias = "refactor";
          description = "重构选中代码并用中文说明";
          prompt = "请重构以下 %s 代码：保持行为不变，提升可读性与健壮性。先用中文说明改了什么、为什么，再给出完整代码：";
        };

        "实现+测试工作流" = {
          interaction = "chat";
          description = "实现 → 写测试 → 跑测试并修复 (agentic)";
          opts.is_workflow = true;
          prompts = [
            [
              {
                role = "user";
                opts.auto_submit = false;
                content = "你是结对编程助手。请用 @{insert_edit_into_file} 直接修改文件来实现下面的需求；动手前先简要说明思路。需求：";
              }
            ]
            [
              {
                role = "user";
                opts.auto_submit = true;
                content = "现在为上面的实现编写单元测试，覆盖正常与边界情况，并用 @{insert_edit_into_file} 写入对应的测试文件。";
              }
            ]
            [
              {
                role = "user";
                opts.auto_submit = true;
                content = "用 @{run_command} 编译并运行测试。若有失败，分析原因、用 @{insert_edit_into_file} 修复后重新运行，直到全部通过。";
              }
            ]
          ];
        };
      };

      extensions = {
        history = {
          enabled = true;
          opts = {
            auto_save = true;
            auto_generate_title = true;
            title_generation_opts = {
              adapter = "deepseek";
              model = "deepseek-chat";
            };
            continue_last_chat = false;
            keymap = "gh";
            save_chat_keymap = "sc";
          };
        };

        mcphub = {
          callback = "mcphub.extensions.codecompanion";
          opts = {
            show_result_in_chat = true;
            make_vars = false;
            make_slash_commands = true;
          };
        };
      };
    };
  };

  extraPlugins = [ pkgs.vimPlugins.codecompanion-history-nvim ];

  extraFiles = {
    "lua/cc_fidget.lua".source = ./lua/cc_fidget.lua;
    "lua/cc_inline_indicator.lua".source = ./lua/cc_inline_indicator.lua;
  };

  extraConfigLua = ''
    require("cc_inline_indicator").setup()
    require("cc_fidget").setup()
  '';

  autoCmd = [
    {
      event = "FileType";
      pattern = "codecompanion_cli";
      callback.__raw = ''
        function(args)
          vim.schedule(function()
            for _, win in ipairs(vim.fn.win_findbuf(args.buf)) do
              vim.wo[win].number = false
              vim.wo[win].relativenumber = false
              vim.wo[win].signcolumn = "no"
              vim.wo[win].foldcolumn = "0"
            end
          end)
        end
      '';
    }
  ];

  keymaps =
    let
      nv = [
        "n"
        "v"
      ];
      mkMap = mode: key: action: desc: {
        inherit mode key action;
        options.desc = desc;
      };
      lua = code: { __raw = code; };
    in
    [
      (mkMap nv "<leader>aa" "<cmd>CodeCompanionChat Toggle<cr>" "CodeCompanion: toggle chat")
      (mkMap nv "<leader>ap" "<cmd>CodeCompanionActions<cr>" "CodeCompanion: action palette")
      (mkMap "v" "<leader>av" "<cmd>CodeCompanionChat Add<cr>" "CodeCompanion: add selection to chat")
      (mkMap "n" "<leader>ai" "<cmd>CodeCompanion<cr>" "CodeCompanion: inline assistant")
      (mkMap "v" "<leader>ai" ":CodeCompanion<cr>" "CodeCompanion: inline assistant (selection)")
      (mkMap "n" "<leader>at" "<cmd>CodeCompanionCLI<cr>" "CodeCompanion: CLI (default agent)")
      (mkMap "n" "<leader>ah"
        (lua "function() require('codecompanion').extensions.history.browse_chats() end")
        "CodeCompanion: chat history"
      )
      (mkMap nv "<leader>acp" (lua "function() require('codecompanion').cli({ prompt = true }) end")
        "CLI agent: prompt (selection-aware)"
      )
      (mkMap nv "<leader>aca"
        (lua "function() require('codecompanion').cli('#{this}', { focus = false }) end")
        "CLI agent: add buffer/selection as context"
      )
      (mkMap "n" "<leader>acd"
        (lua "function() require('codecompanion').cli('#{diagnostics} 请修复这些问题', { focus = false, submit = true }) end")
        "CLI agent: fix LSP diagnostics"
      )
      (mkMap "n" "<leader>act"
        (lua "function() require('codecompanion').cli('#{terminal} 这是终端输出，请帮我修复', { focus = false, submit = true }) end")
        "CLI agent: fix terminal output"
      )
      {
        mode = "n";
        key = "<leader>ax";
        action = ":CodeCompanionCmd ";
        options = {
          desc = "CodeCompanion: generate command";
          silent = false;
        };
      }
      {
        mode = "n";
        key = "<leader>aT";
        action = ":CodeCompanionCLI agent=";
        options = {
          desc = "CodeCompanion: CLI (pick agent)";
          silent = false;
        };
      }
    ];
}
