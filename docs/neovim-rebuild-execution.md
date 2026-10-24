# Neovim AI 重构（2026-10-24）

本轮以 `nvim-ai` / `cdbe549` 隔离 worktree 为基线，完整替换键位与 AI 工作流。
配置尚未应用，不执行 sudo、nixos-rebuild 或 Git stage/commit/push。最终构建路径、性能样本、
检查结果和实机待验项记录于[本轮历史](history/nvim-ai-2026-10-24.md)。
完整新键位及旧→新对照见[工作流键位表](workflow-design.md#neovim-键位)。

## AI 三层与补全

1. **claudecode.nvim** 是 Claude Code 的 IDE 协议入口：跟踪当前文件、打开文件和选区；
   `<Space>ac` 由插件自己的 Snacks 终端启动 Claude，宽屏右侧固定，窄屏浮动。
   `<Space>as` 发送可视选区。Claude 的 `openDiff` 会在独立标签页打开左右原生 diff，
   隐藏终端并聚焦建议，配色与 codediff/mini.diff 统一。顶部显示接受/拒绝提示；
   在建议缓冲区用 `,a` / `<Space>aA` 接受，`,r` / `<Space>aD` 拒绝，可先手动编辑建议。
   每次审阅对应一个文件提案，不是逐 hunk 批准。锁定 0.3.0 的接受命令返回 `FILE_SAVED`
   与编辑后的文本给 CLI，由 CLI 写入目标文件；CLI 随后 `close_tab` 清理视图。
   拒绝返回 `DIFF_REJECTED`，不会写源文件。未保存的原文件会被上游拒绝打开 diff。
2. **sidekick.nvim** 管理 Codex/Grok 原生 TUI；`<Space>ax/ag` 切换工具，
   `<Space>af/av/aE/aG` 将文件/选区/诊断/Git diff 交给当前会话。
   没有活跃会话时选择工具。发送只插入上下文，不自动提交。Claude 从工具表移除，避免第二终端。
   CLI 退出后的改动通过 watch/checktime 刷新，保留缓冲区未保存保护。
   NES 与原生 inline completion 共享单个 `copilot` LSP：sidekick 2.3 按客户端名发现它，
   直接调用 `textDocument/copilotInlineEdit`。普通模式 `Tab` 跳到/应用下一编辑，
   没有建议时透传 Tab；插入模式 Tab 由独立幽灵文本模块处理。
3. **CodeCompanion 19.27** 默认 DeepSeek HTTP 对话与内联改写；中文 prompt library 包含解释报错、
   为选区写测试、提交信息草稿、重构与注释。历史扩展保持原目录、自动本地保存、不额外请求标题。
   对话中 `ga` 切换 adapter，可选 `codex` / `claude_code` ACP；这与 CLI 的原生 TUI 是不同入口。
   ACP 使用 llm-agents 的 `codex-acp` 2.2.2 / `claude-agent-acp` 0.95.0，不运行 npx。
   独立 flake 包由 `nix/neovim.nix` 注入绝对路径；HM 消费 ai-workbench 的公开会话变量
   `NVIM_CODEX_ACP` / `NVIM_CLAUDE_ACP`，应用后需新登录会话。无有效路径时报错。

用户在 tmux 自己启动 Claude 时，先在 Neovim 执行 `:ClaudeCodeStart`（只启动 IDE 服务），
再在 Claude 执行 `/ide` 选中这个 Neovim。无需打开插件终端；状态栏 `C●` 表示连接、
`C○` 表示已加载但未连接、`C·` 表示尚未加载。状态栏同时显示 CLI 会话名、补全提供者、请求中。

**AI 只提供灰色行内幽灵文本**，不进入菜单。Copilot 使用 Neovim 0.12.4 原生
`vim.lsp.inline_completion`，Nix 注入 stable `copilot-language-server` 1.495.0 的绝对路径，
不使用 npm。首次打开普通文件，等待 Copilot LSP attach 后执行 `:LspCopilotSignIn`，按浏览器
设备码流程登录；退出登录用 `:LspCopilotSignOut`。这两个 buffer-local 命令来自锁定 lspconfig
的 `lsp/copilot.lua`。认证由服务器在运行时管理，不读取或迁移既有凭据。
`␣au` / `␣ua` 或 `:AICompletion copilot|deepseek|off` 三态切换。DeepSeek 使用 Minuet
virtualtext 前端，仅读 `DEEPSEEK_API_KEY`，不写入 Nix/store；使用 FIM beta/completions。
无 Key 显示说明；不会自动切到付费兜底。切换后丢弃晚到 DeepSeek 响应并关闭其他引擎与 NES。
菜单打开时隐藏幽灵文本。插入 `Tab` 接受整条建议；`Ctrl+→` / `Alt+l` 接受一个词，
`Alt+]` / `Alt+[` 轮换，`Esc` / `Ctrl+]` 拒绝。Tab 无建议时跳原生片段，再回退缩进。

**从 blink 换到原生补全**是因为用户只需要基本 LSP，AI 已独立，不再需要多源合并、
额外的菜单框架和 Rust fuzzy 库。LspAttach 用 `vim.lsp.completion.enable` autotrigger，
kind 图标复用 kinds、detail 截短；`menuone,noselect,popup,fuzzy` 保持不预选。
0.12.4 文档明确 nearest 与 fuzzy 同时存在时无效，因此保留 fuzzy，不叠加 nearest。
菜单高宽受限，Pmenu 系列接 palette；pumborder/winborder 均 rounded，原生 popup 显示文档，
该版本没有 completepopup 选项。`Ctrl+y` / Enter 显式确认所选项，Enter 未选择时换行；
`Ctrl+n/p` 上下，`Ctrl+e` 关闭，`Ctrl+Space` 请求 LSP。C++ 自有 JSON 片段通过 complete 的
F/completefunc 源进入候选，用 `vim.snippet.expand` 展开；可 `Ctrl+x Ctrl+u` 专门触发。
路径补全保持 `Ctrl+x Ctrl+f`。命令行 `wildoptions=pum,fuzzy`，Tab 触发；不额外自动弹菜单。
lazydev 继续给 LuaLS 注入 workspace library，不再配置菜单 source。

CodeCompanion 19.27 仍未提供旧 `display.diff.provider` 选项。`cc_minidiff.lua` 对其
`helpers.show_diff` 的 inline 分支做小型兼容桥：mini.diff 叠加预览，`,a` 接受保留未保存内容，
`,r` 拒绝还原，禁止同一 buffer 重叠审阅，恢复原局部键位。其他 CodeCompanion diff 沿用上游。
Gitsigns 单独拥有 Git sign 列；mini.diff 只在内联审阅时用行号/overlay，不启动 Git source。
升级 CodeCompanion/Minuet 时要复核两个回调桥，相关行为测试会执行真实 MiniDiff/Claude diff。

## 插件与加载

删除 nvim-dap、dap-view、dap-virtual-text、Nix 的 LLDB/debugpy 注入和全部调试键；
删除 overseer 与任务模板，用项目终端/AI CLI 跑项目任务；删除 smear-cursor，避免与 Kitty
cursor_trail 重复。最新原生替换见下表；文件安全和用户状态保留。
claudecode、sidekick、Minuet、mini.diff、edgy、smart-splits 与 codediff 来自锁定 stable。
独立 flake 包的 CodeCompanion 使用既有 pkgs-unstable 参数选择 19.27.0；原因是 19.13 缺少后续修复与 ACP
改进，v20 有破坏性变更，待 nixpkgs 收录后另行迁移。其 Plenary runtime 依赖保持 stable，
避免混入第二个 LuaJIT；锁定 history 扩展保持原版本，真实 setup 与存储兼容性由 checks 验证。

保留 lz.n 按事件/命令/键位加载。五个启动插件仍为 lz.n、One Dark、Heirline、Snacks、devicons；
CodeCompanion/Claude 按命令或按键，Minuet 手动切换后加载；Copilot 配置随 LSP 初始化，
服务器按普通文件 attach。Edgy/smart-splits 由 MayonVeryLazy 或方向键加载。
空启动性能预算为三次独立 HOME/XDG 的 NVIM STARTED 中位数 ≤30ms，样本见历史。

## 原生能力替换表

依据是锁定 0.12.4 runtime 的 doc/news.txt、doc/lsp.txt、doc/options.txt 及 pack/dist/opt，
[上游原生 LSP 文档](https://neovim.io/doc/user/lsp/)只作背景，实际版本 API 以本机源码为准。

| 替换前 | 替换后 | 行为与边界 |
|---|---|---|
| blink.cmp 与 AI source | 原生 LSP 菜单 + 独立幽灵文本 | 少量 LSP 需求；片段/路径走原生；无 AI 菜单项 |
| copilot.lua / copilot-lsp | inline_completion + Nix Copilot server | 同一个 client 供 Sidekick NES 使用 |
| Noice / nui | `vim._core.ui2.enable()` | 实验接口；消息 pager 为 buffer，命令行实时高亮；通知仍 Snacks |
| 自写 LSP progress 聚合 | Progress + `vim.ui.progress_status()` / busy | 状态栏读取原生摘要 |
| 无撤销树入口 | `packadd nvim.undotree` + `:Undotree` | `␣su` 按需加载，原 undo 数据保留 |
| Flash 的 S 语法选择 | 原生 an/in、节点移动、Treesitter select | LSP selectionRange fallback；Flash 只用 s 跳转 |
| 手动 LSP 扩展 | 原生 CodeLens/linked editing/on-type/document color | 按 supports_method；`␣uL` 按需打开 CodeLens |
| colorizer 包含 CSS/HTML | LSP 处理支持的 document color | colorizer 只负责 Lua/Nix，避免重复覆盖 |
| 单一诊断列表 | 原生 workspace_diagnostics | `␣xw` 收集工作区诊断，Trouble 入口仍保留 |
| 无原生 restart/目录比较入口 | `:restart` / `:DiffTool` | `␣qr` / `␣gT`；关闭迁到 `␣qq` 避免 leader 前缀冲突 |
| 默认字符 diff | `diffopt+=inline:word` | 原生 Claude diff 与其它 diff 保持统一配色 |
| 自维护 Git fork | codediff 2.45.0 + libvscode_diff | Nix 构建原生库，禁止在线安装 |

ui2 headless 是否可用与构建测试结果见历史，不把实验接口写成稳定保证。
CodeLens 默认关闭按需显示；0.12.4 自动 CodeLens 晚到响应在删除 buffer 后可触发无效 buffer
redraw，隔离测试已复现，故不在 attach 时自动请求。linked editing、on-type formatting 与颜色
仅在服务器声明支持时启用；签名帮助在 `(` / `,` 后请求。注释已用原生 gc，无额外注释插件；
插件仍由 Nix 管理，不使用 vim.pack。

## Git 审阅与 codediff

`␣gd` 打开工作区，`␣gf` 当前文件历史，`␣gD` 输入提交/分支比较，`␣gC` 当前文件冲突；
`␣gT` 使用 Neovim 自带 DiffTool 比较目录。CodeDiff 同时支持行级与字符级高亮、并排与内联，
审阅本地、暂存、提交或远程 PR 的已获取 refs，以及文件历史和冲突逐块解决。
PR refs 需先由外部 Git 获取，不会替用户执行联网 checkout。界面 `t` 切换布局，实际键位见
`:h codediff-keymaps`；保留 Gitsigns 的 hunk 暂存/还原与 LazyGit。
Explorer 左侧 30 列、树形图标与 Edgy 文件树相同；独立 Git 审阅 tab 的窗口仍由 codediff 管理。
字符增删与原生 diff/Claude 使用同一 palette；Claude 继续用 `,a/,r` 接受/拒绝整文件提案，
codediff 的工作区视图只审阅已有文件变化，不等同 Claude 协议接受。

已复核保留：heirline（API 稳定且自写状态/标签栏成熟）、nvim-autopairs（blink.pairs 尚年轻）、
surround、edgy、trouble、todo-comments、flash 跳转、multicursor、oil、yazi、grug-far、conform、
nvim-lint、render-markdown、rainbow-delimiters 和限定 filetypes 的 colorizer。
这些保留项未作行为重写。此前保留 blink/Noice 的结论已被最新用户需求覆盖。

## 布局、语言与状态

Edgy 左 Explorer，右 Claude/CodeCompanion/sidekick，下 Trouble、quickfix 与普通终端；
小窗口不固定左右侧栏，AI 创建时用浮窗。统一标题、圆角浮窗和 palette 面板/diff 高亮。
Ctrl+h/j/k/l 用 smart-splits 穿过 Neovim 与 tmux 面板，Alt+h/j/k/l 调整大小。
本轮未修改超出写入范围的 tmux 配置，主代理需合入历史文件中的 tmux 片段。
真实 tmux、TTY Alt/Tab、窗口缩放和美观仍需实机验收。

原生 LSP、basedpyright、Taplo、Treesitter、flash、多光标、surround、Oil/Yazi、Snacks、Markdown、
公式预览、会话/草稿/URL、Heirline、which-key、Satellite、tiny-inline-diagnostic、TODO、
rainbow、colorizer 和 gitsigns 保留。语言工具与 parser 仍由原有契约生成。
undo、会话、草稿、shada 和 AI 历史保持原路径及格式，不转换或清除用户数据。
Oil 继续回收站删除、独占复制、拒绝覆盖或符号链接目标；不清理普通源文件 undo。

## 验证边界

检查含原有 startup/completion/integration/workflow/fileops/lua_workspace/modern/interface、六语言首文件、
真实 CSS 未保存诊断、normal/dev/reduced wrapper 与故意失败 runner；新增 AI 加载、ACP 可执行路径、
补全切换、多 buffer/晚到响应、真实 mini.diff 接受/拒绝、Claude 协议 diff 接受/拒绝与键位 API 扫描。
`nvim_get_keymap` 只能看到最终有效映射，重复扫描不证明初始化期间没有覆盖；另检查 leader 叶节点前缀冲突。

求值、构建、隔离 headless 与实机验证分开记录。不把 mock 回调或协议 fixture 当成联网模型请求、
Claude CLI 实际写盘或 GUI 美观的证明。实际 health、构建命令与限制见本轮历史。

## 待办

- 微信输入法问题待解决：主代理实测 XCB/Fcitx wrapper 无效，本轮撤销为直接安装 wechat；
  问题挂起，不改用户数据。上一轮 wrapper 构建记录保留作历史，不能视为实机成功。
- 应用后验收 Copilot 登录、灰色建议/逐词/候选/菜单互斥、Sidekick NES；DeepSeek 实际 FIM；
  codediff 暂存/提交/PR/冲突、ui2 真实 TUI 命令行/pager、restart 保留 UI、窄屏和 Alt 按键。

范围限制：Home Manager 的工厂调用在 aspects/editing/default.nix，超出本轮可写范围，且原来
没有传入 pkgs-unstable。已向主代理请求仅增补该参数的授权；在接线前，HM 调用保留 stable
19.13，独立 neovim/neovim-dev 包为 19.27。不得把独立包升级写成系统内已升级。
