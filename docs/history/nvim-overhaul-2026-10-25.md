# Neovim 全面改造 · 2026-10-25

本轮接续[第二十二轮视觉修正](nvim-visual-2026-10-25.md)，并按 Islands / One Dark 工作区重新整理 Neovim 与 Kitty。配置与功能说明见 [Neovim README](../../aspects/dev/neovim/README.md)。E 节覆盖与 D 节冲突处：dropbar 取代 navic，面包屑放编辑区顶部。另一工作树的 GTK/Qt 主题不在本轮范围内。

截图和运行时记录来自隔离的 headless sway + 真实 Kitty，不是在用户会话内启动窗口。环境按 2560×1600、scale 1.5 配置；wayland/logical 尺寸会因像素取整不同。图集入口：`/tmp/claude-1000/-home-mayon-nix-dotfiles/13f9340b-d643-4d3f-bd2f-97266d0e2965/scratchpad/r22/index.html`；65 张最终图（64 类 Neovim/Kitty 界面，加 1 张 Zathura 正向搜索），逐项映射见同目录 `r23/gallery-index.json`，捕获清单见 `r23/gallery-manifest.json`。

## 截图迭代

迭代记录不是效果保证；下面只说明有文件可核对的截图与 Kitty 日志。前态对照为第二十二轮实机截图 `.../scratchpad/r22/9.png`、`10.png`。

| 轮次 | 证据 | 处理 / 对照要点 |
|---|---|---|
| iter1 | `.../scratchpad/r22/r23/iter1-dashboard.png`、`iter1-editor.png`；`r23/kitty-iter1.log` | 第一轮真实 Kitty 基线，记录 dashboard 与编辑器整体表面。 |
| iter2 | `.../scratchpad/r22/r23/iter2-editor.png`；`r23/kitty-iter2.log` | 捕获出浮窗标题布局触发 E36 的问题；调整 ownership，避免与 Snacks / ui2 的浮窗职责冲突。 |
| iter3 | `.../scratchpad/r22/r23/iter3-editor.png`、`iter3-explorer.png`；`r23/kitty-iter3.log` | 发现左右 rails 位置不对，按工作区结构修正布局，再核对 Explorer 和编辑区。 |
| iter4 | `.../scratchpad/r22/r23/iter4-editor.png`；`r23/kitty-iter4.log` | 发现 mini.map 过亮；改为 muted，并将地图宽度收至 8 列。 |
| iter5 | `.../scratchpad/r22/final-editor-explorer.png`、`final-ai-panel.png`；`r23/kitty-iter5.log` | 最后一轮检查静态工具栏和 AI surface 一致性，随后补录 dashboard、picker、诊断及其他界面。 |

迭代 PNG 与最终图集 PNG 均在上述 scratchpad 临时目录，未复制进仓库。捕获清单含重复 retake，不将其累计条数当作唯一界面数。dropbar 初次调用曾被 SIGTERM，之后有成功的 `final-dropbar.png` 与 `final-dropbar-menu.png`；cmdwin 最初捕获被 Keyboard interrupt，后续已成功重录 `final-cmdwin.png`。

## A–C：布局、功能与终端结果

“有证据”表示配置/测试或隔离 Kitty 截图能支持所述范围，不代表在用户当前运行会话中已应用。

| 项 | 结果 | 证据与边界 |
|---|---|---|
| A1 sign / 行号 | 已实现并截图 | 固定 sign 槽；gitsigns 变更细条、诊断级别小标记；无折叠列。见 `final-editor-explorer.png`、`final-diagnostic.png`。 |
| A2 非活动窗口 | 已实现并截图 | NormalNC 较暗，CursorLine 限于活动窗口。见 `final-editor-explorer.png`。 |
| A3 面包屑 | 已实现并截图 | dropbar 取代 navic；路径、文件、符号可点选并可打开同级菜单。见 `final-dropbar.png`、`final-dropbar-menu.png`。 |
| A4 浮窗 | 已统一并抽样截图 | 浮窗采用 deep 底、muted 边缘/圆角与统一标题处理；hover、signature、diagnostic、input/select、通知等见 F 表。第三方 CLI 的终端内容仍由其自身绘制。 |
| A5 辅助面 | 已覆盖并统一样式 | health、messages、ui2 pager、help、man、cmdwin 均有捕获；最终 health 为 0 ERROR。最终 health 的 7 条 WARNING 及解释见 B19。 |
| A6 Zen | 已实现并截图 | `Space uz` 专注模式；见 `final-zen.png`。 |
| B1 Tree-sitter | 已实现并通过配置/功能检查 | 已打包 parser 在首个文件打开前加入 runtimepath，未因此触发插件脚本加载；Markdown 注入见 `final-markdown-injection.png`。health 只报告可选 norg parser 缺失，不影响已打包 parser。 |
| B2 LaTeX | 部分实测 | texlab PDF 输出、逆向 RPC 及真实 Zathura 正向搜索已测试（`r23/zathura-forward.json`、`final-zathura-forward.png`，公式位置有绿色定位）；LaTeX 高亮见 `final-latex.png`。PDF 中 Ctrl-click 逆向手势未模拟，因此不宣称双向 GUI 手势完整验收。build-on-save 为可选；键位见 README。 |
| B3 Mermaid | 已按设计禁用 | 不安装重型 mmdc；Snacks image 的 Mermaid 转换关闭，health 显示 “Mermaid rendering disabled by configuration”，不把它当依赖缺失错误。 |
| B4 Snacks 集成 | 已实现并截图 | dashboard setup、input、picker `ui_select`、toggle/which-key 接线通过 health/集成检查；见 `final-dashboard.png`、`final-input.png`、`final-select.png`、`final-which-key.png`。 |
| B5 Neovim 版本 | 已切至锁定 unstable 0.12.6 | 构建验证覆盖 normal、dev、HM 0.12.6 包；没有更新 flake lock。最终 HM 包与 flake 包路径见验证记录。 |
| B6 lua_ls | 已实现并通过 workspace 检查 | Neovim runtime 和插件库范围、`vim`/`Snacks` globals 配置到 lua_ls；health 中配置仓库附着 lua_ls。 |
| B7 CodeDiff | 异步流程回归通过 | 原回调错误由测试仓库在异步加载结束前被清理触发；回归等待实际前后文件 buffer 就绪并关闭 review 后再清理，不声称修复了未经证实的上游缺陷。临时 Git fixture 覆盖异步加载；测试使用 Git plumbing 建 fixture，不对真实仓库执行 add/commit/push。见 `final-git-review.png`、`final-git-history.png`、`final-git-conflict.png`。 |
| B8 Python | 已配置并通过语言检查 | basedpyright standard、Ruff diagnostics/organize imports、ruff_format；禁用重复 Ruff 诊断路径。实际体验受项目环境/依赖影响。 |
| B9 C/C++ | 已配置并通过语言检查 | clangd 参数、clang-format、`Space ch` 头源切换和 compile_commands 提示；见配置和语言检查。未据此宣称外部大型 C++ 项目索引基准。 |
| B10 Nix | 已配置并通过语言检查 | nixd 选项补全绑定本 flake 的 `nixos-btw` NixOS/HM options；nixfmt 格式化。 |
| B11 Rust / Go | 条件支持 | parser 随包提供；rust-analyzer / gopls 仅在 PATH 存在时启用。没有全局安装这两个 LSP；应由项目 devshell/direnv 提供。 |
| B12 Git | 已实现并通过临时仓库检查 | gitsigns 管 sign/hunk，blame 默认关闭、`Space gb` 切换；mini.diff 仅用于 CodeCompanion inline diff、不绘制 sign。Lazygit 和 Neogit 并存；冒烟检查没有实际提交或推送。截图见 F 表。 |
| B13 折叠 | 已实现并通过功能检查 | 优先 LSP、否则 Tree-sitter foldexpr；默认展开；foldtext 为首行加 `… N lines`。 |
| B14 会话 | 已实现并通过跨进程回归 | 按项目自动存取普通文件布局，保存前过滤 Explorer/AI/terminal/tool buffers。独立的第一进程保存、第二 fresh 进程从 dashboard 恢复；修复恢复时 dashboard 插件已先行删除 buffer 导致的过期 buffer id 访问。未读取或改动用户已有会话数据。 |
| B15 剪贴板 | Wayland 真实剪贴板往返通过；SSH OSC 52 provider 检查通过 | 隔离 Wayland session 的 Unicode `setreg/getreg` 往返一致，证据 `r23/clipboard-wayland.json`；SSH headless 输出确认 provider 为 OSC 52 且 copy 函数可用，证据 `r23/clipboard-ssh.json`。未在用户会话读写剪贴板。 |
| B16 拼写 | 已配置并截图 | Markdown、gitcommit、TeX 使用 `en,cjk`，其他文件类型关闭；见 `final-spell.png`。 |
| B17 AI 流程 | 离线验证 | Claude Code 命令/选区/diff 接受拒绝、Sidekick Codex/Grok、Copilot 和 Minuet 切换、CodeCompanion 默认 DeepSeek 及缺少凭证的中文提示通过离线接口/命令检查。面板截图是隔离演示状态；没有凭证，没有模型请求，也没有声称实际登录服务成功。 |
| B18 键位 | 已检查并截图 | Space 全局 which-key 视图（`Space ?`）、分组与冲突检查；截图 `final-which-key.png`。Vim 原生操作映射仍可用。 |
| B19 health | 通过：0 ERROR、7 WARNING | 在真实隔离 Kitty GUI 加载全部 32 个 plugin specs 后执行 checkhealth，记录于 `r23/health-final.txt`。7 条 warning：ast-grep 未安装（grug-far 可选增强）、norg parser 缺失及依赖它的文档渲染提示（2 条）、mini.icons 未安装（使用现有彩色 devicons）、gc/gcc 及 ys/yss、yS/ySS 三组原生前缀重叠（which-key 的信息提示）。没有将这些提示误报为错误。 |
| B20 性能 / 大文件 | 启动中位数达标；大文件保护通过 | 最终 headless 11.989 ms、Kitty 首帧 28.8525 ms、tmux 内首帧 28.1485 ms。1.31 MB fixture 关闭 Tree-sitter/滚动动画，一次 G→gg seek 0.097 ms（不是长期 FPS 基准）；见 `r23/startup-final/report.json`、`bigfile.json` 与 `final-bigfile.png`。 |
| C1 tmux | 已配置并截图 | tmux 的 allow-passthrough、set-clipboard、focus-events 均为 on（`r23/tmux-options-final.json`）；真实 Kitty tmux 内 Neovim 与 kitty graphics image 分别见 `final-tmux-nvim.png`、`final-tmux-image.png`。不在用户 tmux 会话执行。 |
| C2 Kitty | 已配置并实机隔离捕获 | Kitty padding 收至 4px，OSC 11 与 Neovim Normal 背景同步，退出/挂起恢复、恢复后重新应用；见第二十二轮记录及本轮 Kitty 图集。Kitty scrollback 保留原生 pager，因为终端回滚内容是 ANSI 输出；没有改为 Neovim pager。 |

### D：IDEA Islands 布局状态

| 项 | 结果 | 证据 / 限制 |
|---|---|---|
| D1 Islands | 已实现并截图 | frame 为 deep 派生色 `#090a0c`，bg 岛与 seam 区分；约 1.30:1 装饰性对比，不作为正文对比度。见 `final-editor-explorer.png`。 |
| D2 工具栏/标签 | 已实现并截图 | 顶部项目、分支、Search Everywhere、上次 task、AI/设置入口；编辑区文件标签显示修改态。见 dashboard、editor/explorer 与 picker 图。 |
| D3 工具栏 | 已实现并截图 | 左右 rail 可打开 Project、Commit、Structure、Bookmarks、Terminal、Problems、History、AI、通知；见 editor/explorer、aerial、neogit、terminal、problems、AI 截图。 |
| D4 工具窗口 / Tasks | 已实现并截图 | Project、Aerial、Neogit、Trouble、Snacks terminal；Tasks 从 justfile/Makefile/flake apps/package.json scripts 探测，显式运行并缓存最近选择。见 `final-tasks.png`。任务命令被设计为用户选择后执行；本轮验证不执行真实 commit/push。 |
| D5 编辑区 | 已实现并截图 | sign 槽、活动行、Copilot ghost text / inlay hints 状态、宽屏 mini.map、dropbar 顶部导航；mini.map 在 `final-editor-explorer.png` 右侧可见，iter4 调成 muted、宽 8 列。 |
| D6 AI 岛 | 离线状态截图 | Claude/Codex/Grok/DeepSeek 面板框架见 `final-ai-panel.png`、`final-claude-panel.png`、`final-codex-panel.png`、`final-grok-panel.png`；无凭证，消息/连接状态为验证用隔离内容，不代表真实模型连接。 |
| D7 状态栏 | 已实现并截图 | 路径、diagnostic、LSP、AI completion、位置、编码/缩进、branch、通知；见 `final-editor-explorer.png`。 |
| D8 Search Everywhere | 已实现并截图 | `Space Space` + Tab 多来源搜索，All/Files/Symbols/Actions/Text；见 `final-picker.png` 与各专用 picker 图。 |
| D9 键位 | 已实现并检查 | Alt-1/2/7/F12 在 Neovim 可用范围分别打开工具面板；与窗口/tmux 组合键协调，保留 Space leader。which-key 可查。 |
| D10 窄屏 | 已实现并截图 | 小于 140 列收起侧岛；见 `final-narrow.png`。 |

### E：社区细节

| 项 | 结果 | 证据 / 限制 |
|---|---|---|
| E1 dropbar | 已实现 | 替换 navic；顶部可点面包屑及同级选择。见 `final-dropbar.png`、`final-dropbar-menu.png`。 |
| E2 highlight-colors | 已实现并截图 | nvim-highlight-colors 显示色块，关闭命名颜色背景染色；见 `final-colors.png`。 |
| E3 tiny-glimmer | 已实现并通过配置检查 | 编辑动作的短时反馈、reducedMotion 抑制；没有逐一录制每种动画。 |
| E4 模式颜色 | 已实现并截图 | CursorLineNr 与状态栏模式块按 Normal/Insert/Visual/Replace/Command 变色；编辑器图为抽样。 |
| E5 诊断 | 已实现并截图 | tiny-inline-diagnostic 光标行淡色胶囊、其余行下划线；见 `final-diagnostic.png`、`final-diagnostic-float.png`。 |
| E6 折叠 | 已实现并截图 | `… N lines` foldtext；见 `final-fold.png`。 |
| E7 搜索计数 | 已实现 | 计数收在状态栏，未另做右上角浮窗；这是 README 中当前行为。 |
| E8 平滑滚动 | 已配置并通过功能检查 | Snacks.scroll 短时滚动，bigfile/录制等情况抑制，尊重 reducedMotion；无单独动效视频。 |
| E9 indent / words | 已启用 | Snacks.scope 与 words；配置/健康检查为证，没有独立视觉截图。 |
| E10 额外插件 | 未新增无验证的插件 | 采用已锁定并集成的 dropbar、Snacks、tiny-glimmer 等；没有因“社区精选”再叠加未经测量的新依赖。 |

## F：界面清单 × 处理 × 截图

路径统一以 `/tmp/claude-1000/-home-mayon-nix-dotfiles/13f9340b-d643-4d3f-bd2f-97266d0e2965/scratchpad/r22/` 为前缀。表中 PNG 名称可与前缀拼接。图集索引为该目录 `index.html`。

| 界面 / 窗口 | 处理方式 | 截图 |
|---|---|---|
| Dashboard / 项目启动 | 最近文件、项目/会话操作、紧凑 action grid | `final-dashboard.png` |
| Project / Explorer 与编辑器标签 | Islands、图标、截断保护、缩进与标签 | `final-editor-explorer.png` |
| Picker：All / Files / Buffers / Recent / Projects | 同一边框/标题/selection 语言 | `final-picker.png`, `final-picker-buffers.png`, `final-picker-recent.png`, `final-picker-projects.png` |
| Picker：Symbols / Actions / Text / Diagnostics / Help / Keymaps | 按来源使用 picker 布局和统一选择态 | `final-picker-lsp_symbols.png`, `final-picker-grep.png`, `final-picker-diagnostics.png`, `final-picker-help.png`, `final-picker-keymaps.png` |
| Dropbar 与下拉菜单 | 可点击 muted breadcrumb 和菜单表面 | `final-dropbar.png`, `final-dropbar-menu.png` |
| Completion / signature / hover | completion 面板与统一浮窗 | `final-completion.png`, `final-signature.png`, `final-hover.png` |
| Diagnostics / Trouble | 光标行 inline、浮动诊断、Problems 列表 | `final-diagnostic.png`, `final-diagnostic-float.png`, `final-problems.png` |
| Input / Select / Confirm | Snacks.input、picker select、确认浮层 | `final-input.png`, `final-select.png`, `final-confirm.png` |
| Help / Man / Quickfix / Loclist | 辅助缓冲区统一配色与边界 | `final-help.png`, `final-man.png`, `final-quickfix.png`, `final-loclist.png` |
| Command window (cmdwin) | 已成功重录；适配原生 cmdwin 与 ui2 界面职责 | `final-cmdwin.png` |
| Terminal / Tasks | bottom terminal 与任务选择界面 | `final-terminal.png`, `final-tasks.png` |
| Oil / grug-far | 文件操作与查找替换界面 | `final-oil.png`, `final-grug-far.png` |
| Aerial / Structure | 符号大纲 | `final-aerial.png` |
| Neogit 主面 / commit popup / log | 统一 Git 表面；只检查界面与流程，不执行真实提交 | `final-neogit.png`, `final-neogit-commit-popup.png`, `final-neogit-log.png` |
| Lazygit | CLI 终端面板，内部内容由 lazygit 绘制 | `final-lazygit.png` |
| CodeDiff review / history / conflict | 审阅、历史和冲突对照面板 | `final-git-review.png`, `final-git-history.png`, `final-git-conflict.png` |
| Claude diff | 原生 diff split 样式 | `final-claude-diff.png` |
| Claude / Codex / Grok / AI 通用面板 | 离线 mock/空态面板；未认证、未请求模型 | `final-ai-panel.png`, `final-claude-panel.png`, `final-codex-panel.png`, `final-grok-panel.png` |
| Health / messages / ui2 pager | health surface、消息历史和 ui2 阅读面；最终 health 以文本运行记录为准 | `final-health.png`, `r23/health-final.txt`, `final-messages.png`, `final-ui2-pager.png` |
| Which-key / notifications history | 全局键位图、通知层与历史列表 | `final-which-key.png`, `final-notifications.png`, `final-notifications-history.png` |
| Confirm dialog | Snacks confirm 与原生确认框 | `final-confirm.png`, `final-confirm-native.png` |
| Zen / marks / spell suggestions | 专注模式、marks picker、拼写建议 | `final-zen.png`, `final-marks.png`, `final-spell.png` |
| Fold summary / color swatches | 折叠胶囊与虚拟色块 | `final-fold.png`, `final-colors.png` |
| Narrow workspace | 窄于 140 列时自动收起侧岛 | `final-narrow.png` |
| Inspect / LaTeX / Markdown injection | Inspect 高亮组、TeX 文档、Markdown 注入 | `final-inspect.png`, `final-latex.png`, `final-markdown-injection.png` |
| Zathura SyncTeX forward search | texlab build 后同一隔离 Wayland 中打开 PDF，并绿色定位公式 | `final-zathura-forward.png`; 运行记录 `r23/zathura-forward.json` |
| tmux 中的 Neovim | 隔离 Kitty/tmux 组合窗口 | `final-tmux-nvim.png` |
| tmux 内 Kitty graphics image | tmux 透传后显示公式图片 | `final-tmux-image.png`；tmux 的 allow-passthrough、set-clipboard、focus-events 均为 on（`r23/tmux-options-final.json`） |
| mini.map | 宽屏地图可见，muted 样式与 8 列宽度 | `final-editor-explorer.png` 右侧 |

## 验证记录与限制

- **完整构建验证**：最终代码快照 `source-r23-23` 的 flake 求值退出码 0（37.8s），全部 28 checks、normal/dev/HM 包、Kitty/tab bar/tmux 配置与系统 toplevel 的单次串行构建退出码 0（46.7s，含 `--print-out-paths`）。记录保存为 `r23/source23-verification.json` 与 `source23-all-checks-toplevel.log`。交付快照的最终命令、退出码和全部 store 输出以 `r23/verification.json`、`r23/all-checks-toplevel.log` 为准。所有新增 Lua 文件进入经过白名单过滤的源码快照；未 stage/commit 或激活配置。health 全 specs / 零 ERROR 断言另由真实 GUI 手动执行，不在每次 headless suite 中启动。
- **运行时 health**：最终输出 `r23/health-final.txt` 在真实隔离 Kitty GUI 加载 32 个 plugin specs 后运行，0 ERROR、7 WARNING。告警分别为 ast-grep 缺失 1 项、可选 norg parser/文档渲染提示 2 项、mini.icons 未安装 1 项、which-key 报告 gc/gcc、ys/yss、yS/ySS 三组原生键位前缀重叠 3 项。更早的 `health-iter4.txt` 记录过 rainbow-delimiters 错误空报告及 sqlite3/init 相关问题；后续已修正，不能拿旧文件代表最终状态。`final-health.png` 和文本由同一最终检查捕获；ERROR/WARNING 计数以完整文本为准。
- **临时 Git**：CodeDiff、Neogit/Lazygit 的界面/流程采用临时仓库；不会对主 checkout 执行 add/commit/push。界面截图不证明用户仓库写入流程。
- **会话回归**：live dev 包通过 `config/tests/run.lua` 运行 `workflow.lua` 退出码 0（0.57s）；测试启动两个独立 headless Neovim 进程共享新的临时 HOME/state，先保存再从 dashboard 恢复。该跨进程回归也已包含在随后通过的 Nix checks 中。
- **剪贴板**：`r23/clipboard-wayland.json` 记录隔离 Wayland 下 Unicode 字符串 setreg/getreg 往返一致；`r23/clipboard-ssh.json` 记录独立 headless SSH provider 选择 OSC 52 且 copy 函数存在。没有触碰用户剪贴板。
- **AI**：所有自动化均离线，不使用凭证，不提交模型请求；截图为验证用状态，不证明服务登录或响应质量。
- **TeX**：texlab 生成 PDF 后，正向搜索在隔离 Wayland 实际打开 Zathura 并绿色定位公式（`r23/zathura-forward.json`、`final-zathura-forward.png`）。逆向 RPC 已覆盖含空格文件名与目标行；PDF 内 Ctrl-click 手势未模拟，故不声称整个用户手势链已验收。
- **Rust / Go**：语言服务器按 PATH 条件启动；rust-analyzer/gopls 未全局安装。
- **Kitty**：隔离 headless sway 中的真实 Kitty 捕获已完成，不曾在用户 Wayland 会话打开窗口或模拟按键。Kitty 日志含无 DBus/systemd-user-bus 提示；截图仍成功生成。
- **性能最终值**：每种模式 25 个冷 Neovim 进程，前 5 次 warmup，后 20 次取中位数。headless **11.989 ms**（11.518–12.483），Kitty **28.8525 ms**（25.365–32.610），Kitty/tmux **28.1485 ms**（22.816–38.793），均满足中位数 ≤30 ms；单次最大值不作保证。OS/store 缓存热、AC 在线、performance profile，未清缓存。GUI 数值采用 Neovim `--startuptime` 的 `first screen update` 标记，不包含 Kitty 进程/窗口创建或屏幕扫描输出的墙钟时间。隔离 `-i NONE`；四个 RECENT 文件及彩色 devicons 已由 RPC 断言进入首帧，PROJECTS 列表首帧后填入。完整样本、环境和探针见 `r23/startup-final/report.json`。Dashboard 页脚展示 Lua 配置 setup 时间，不作为启动基准结论。中间测量 source18 30.703 ms、source19 30.231 ms、source21 31.4485 ms 未达目标，未选择性写成最终通过。
- **最终 Neovim 包路径**：HM `/nix/store/vmgxrzvrkyjr0xf73w4y424n304p3xi4-neovim-0.12.6`；dev `/nix/store/lrcgfkybv1rv3x0naj3mm7l6vd96dfck-neovim-0.12.6-dev`；Normal flake 包 `/nix/store/gkbvqqicdjfr86m2xz8zhf6agrl4f9p0-neovim-0.12.6`，更多元数据见 `r23/output-packages-final.json`。系统 toplevel：`/nix/store/vdj452wlixqqqfpagixb9vxzzafimqn2-nixos-system-nixos-btw-26.05.20261021.da6dc0e`。构建没有应用。
- **仍需实机确认**：Zathura PDF Ctrl-click 逆向手势未模拟（正向 GUI 与逆向 RPC 已分别验证）；AI 登录态与真实模型响应未验证。未在用户 Wayland 会话打开窗口、模拟按键或重启服务。截图不能证明模型响应质量、外部大项目索引或长期帧率。
### 最后两处异步边界

真实 Kitty 缩至 121 列时，Explorer 收起后已排队的 Snacks resize 回调访问已释放 preview；回归又捕获 finder 完成时访问已释放 matcher。对锁定 Snacks 2.31 的三处 callback 加 `closed` 防护（resize、逐项 emit、done），保留活动 picker 的行为和正常清理。旧包运行新增 open→resize→close→drain 回归会失败，新包由最终 checks 验证。CodeCompanion chat 的重新生成改用 `,r`，避免占用 LSP 的 `gr` 前缀。

### 性能与资源策略

将 72 个 grammar/query runtime 根目录构建合并为单一 `nvim-parser-runtime`；只链接 `/parser` 与 `/queries`。`r23/parser-runtime-before.json` 与 `parser-runtime-merged.json` 核对 181 个文件 SHA256 全部一致，合并目录不含 plugin scripts。原可选 Tree-sitter 插件依赖图保留。最近项目发现放到 dashboard 首帧后，最近文件与彩色 devicons 保留在首帧；标题上下文每次 render 重算，逐文件项目根仍按原语义解析。曾尝试按外层根复用 recent 路径，被已有嵌套项目断言挡住，已撤回。

### 社区来源与取舍

参考维护者文档：[dropbar.nvim](https://github.com/Bekaboo/dropbar.nvim) 的可交互面包屑替代只读符号路径；[nvim-highlight-colors](https://github.com/brenoprata10/nvim-highlight-colors) 的 virtual 色块避免整块背景染色；[tiny-glimmer.nvim](https://github.com/rachartier/tiny-glimmer.nvim) 为编辑操作提供短时反馈；[Snacks](https://github.com/folke/snacks.nvim) 统一 picker/input、scroll 与 scope。采用仓库锁定包而非运行时下载；动效保持短时并尊重 reducedMotion。
