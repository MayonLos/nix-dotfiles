# Neovim

公开包工厂为 `package.nix`：参数 `pkgs`、可选 `pkgs-unstable`、`palette`、经 languages collector 校验的
`contributions`，以及可选的 `acpAdapters = { codex = "/nix/store/…/bin/codex-acp";
claude = "/nix/store/…/bin/claude-agent-acp"; }`。输出 `normal`、`dev`、`configDir`。
`nix/neovim.nix` 为独立包与检查注入锁定 llm-agents 路径；Home Manager 的调用沿用原有入口，
ACP 经 ai-workbench 公开的 `NVIM_CODEX_ACP` / `NVIM_CLAUDE_ACP` 会话变量交接。
应用后新登录的会话才会拥有这些变量。缺路径时明确报错，不使用 npx 或下载后备。

配置由 Nix 固定插件与工具、Den 提供语言贡献和 palette，lz.n 管理加载；运行时不下载插件。
Copilot 凭据只由 `:LspCopilotSignIn` 管理，DeepSeek 仅读 `DEEPSEEK_API_KEY` 环境变量。
用户 undo、会话、草稿和 CodeCompanion 历史保持原路径，不执行迁移或清理。

Claude Code 由 claudecode.nvim 独占 IDE 协议和终端；sidekick 管理 Codex/Grok TUI 与 NES；
CodeCompanion 默认 DeepSeek 对话/内联，可选择 Codex/Claude ACP。Copilot 为行内补全主源，
Minuet DeepSeek FIM 为手动切换的兜底。详见
[执行说明](../../../docs/neovim-rebuild-execution.md)与[完整键位](../../../docs/workflow-design.md#neovim-键位)。

CodeCompanion 19.27 已移除旧 mini_diff provider；`features/cc_minidiff.lua` 只包装该锁定版本
`helpers.show_diff` 的 inline 分支，其他 diff 使用上游实现。升级时必须复核 helper 参数和返回值。
桥接层逐缓冲审阅，拒绝还原原始内容，接受保留未保存改写，禁用自动批准；Gitsigns 是唯一 Git sign 写入者。
Sidekick 2.3 与原生 `vim.lsp.inline_completion` 共享一个 `copilot` LSP，
可执行文件来自 Nix 的 copilot-language-server。NES 用普通模式 Tab，灰色幽灵文本用插入模式 Tab。
菜单只用原生 LSP；C++ 片段用 completefunc + vim.snippet，路径用 Ctrl+x Ctrl+f。
Git 审阅使用 stable codediff 2.45.0 及随包 libvscode_diff，禁用在线安装。

检查入口为 `checks.neovim`，测试在独立 HOME/XDG 下运行。涵盖原文件安全、LSP 与 UI，
另验证 AI 包加载、ACP 绝对可执行路径、补全切换、mini.diff 审阅、Claude 原生协议接受/拒绝及键位。
模型请求、真实 tmux 导航、窄屏视觉和 GUI 输入法须实机验收。
