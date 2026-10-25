# Neovim R25：极简专注 + Zed

本轮以用户确认的 `ui7/D1.png`、`D2.png` 为唯一布局依据，替代 [R23 Islands 布局](nvim-overhaul-2026-10-25.md)。不改变用户项目、登录状态或运行桌面；没有应用系统配置、提交 Git 或更改 GTK/Qt 文件。

## 布局与问题对应

| 请求 | 实现 | 运行证据（r25 下） |
|---|---|---|
| 1 顶部细栏 | 项目、分支、细线、彩色文件图标、圆角字符胶囊、橙色修改点；右侧搜索提示。移除 Run/AI/设置组件与关闭叉。标签超宽时保持活动文件可见，`+N` 显示准确折叠数量并打开 buffer picker；中键关闭仍保护未保存内容 | `final-default.png`；`overhaul.lua` 的 Unicode/重复文件名/超宽标签断言 |
| 2 默认专注 | 不创建左右工具条、内部标签窗口或默认大纲；编辑器从第 0 列开始，只保留正常 sign/行号槽与淡色 dropbar | `final-default.png`；`overhaul.lua` 窗口数和左边位置 |
| 3 按需侧栏 | `Space e` / `Alt+1` 打开 34 列 Explorer，原生递归 filter、两列缩进、彩色图标、右对齐 Git 状态、蓝色选中条；Aerial/Git/终端/Problems/AI 仅由命令或键位打开 | `final-sidebar.png`；`workflow.lua`、`panels_picker.lua` |
| 4 搜索浮窗 | 居中紧凑单列列表，不默认显示 preview；一条 grep 匹配一行，居中标题 `grep · N matches`，蓝色匹配及选中条，路径放右侧。关闭背景遮罩，保留其后文件树 | `final-grep.png`；`panels_picker.lua` 原生查找及 resize→close 回归 |
| 5 状态栏 | 模式彩点与文字、相对路径、Git 改动；右侧诊断、LSP、AI 补全来源、行列。不默认显示编码/换行/缩进、位置块或通知按钮 | `final-default.png`；`native.lua` 的进度/并发请求回归 |
| 6 移除 mini.map | 删除插件包、补丁、自动打开逻辑及 `Space um`；保留滚动、glimmer、颜色色块、模式色行号 | 包声明及 `interface.lua` |
| 7 启动页 | 保留动作网格与最近文件，统一新顶栏及点状模式栏 | `final-dashboard.png`；`interface.lua` |
| A 旧深色缝隙 | 删除 frame/rail split 与相关 highlight；WinSeparator 是 edge 细线，底色为编辑区。EndOfBuffer 继承窗口底色，WinBar 使用编辑区底色 | `final-default.png`、`final-sidebar.png` |
| B AI 标题 | 顶栏不再有 Run 组件；AI 仅打开时显示其完整模型/连接状态标题 | `final-ai.png` |
| C Aerial | 保留 `Alt+7` / `Space co` 按需开关，无自动打开 | 默认截图；键位回归 |
| D 诊断 | 当前诊断用淡黄斜体 `▲` 单行显示；无括号、箭头或底框。其它位置用降饱和 undercurl/sign。Lua 不自动运行 luacheck，避免与 LuaLS 重复 | `final-robot.png`；`interface.lua`、`lua_workspace.lua` |
| E 项目 Lua 环境 | 编辑器 LuaJIT/runtime globals 只注入自身配置根；有 `.luarc.json`/`.jsonc` 时尊重项目文件；提供 [OC 模板](../../aspects/dev/neovim/templates/README.md)，不修改用户项目 | 真实 LuaLS 的配置根、普通项目和 OC 项目控制测试；`final-robot-configured.png` |
| F 语义色 | LSP 与 Tree-sitter 共用 One Dark 角色：函数蓝、变量 fg、参数橙斜体、字段按类型、defaultLibrary 黄；关键字紫；未定义全局无额外着色 | `interface.lua`；`final-robot.png` |
| G AI 规则 | 仅视觉替代 AGENTS 规则引用为 muted 摘要；buffer 原文及发送 metadata 保留，其它 context 不受影响 | `final-ai.png`；`ai.lua` 的混合 context / 无标题 / 提交前移除测试 |
| H 换行 | `breakindent`、`linebreak` 和淡色 `↳`，续行保持代码缩进 | `final-robot.png` |

## 真实 Kitty 截图

证据根目录：`/tmp/claude-1000/-home-mayon-nix-dotfiles/b828c6bf-b7bc-4369-9089-49cd98d7d17d/scratchpad/r25/`。`index.html` 提供设计稿与截图并排查看。PNG 均由 grim 捕获独立 headless Sway 的真实 Kitty，不是 tmux HTML 渲染。Sway 输出模式为 2560×1600，scale 1.5；分数缩放的捕获高度可能为 1599。HOME、全部 XDG 目录、运行 socket、Wayland 与 DBus 均隔离。

robot 场景是按 D1 代码重建的临时 GTNH fixture，包含未声明的 `computer`、`0xFF4488` 及刻意加长的字符串；没有改用户项目。AI 截图使用真实 CodeCompanion buffer 加本地 fixture/context，不发送模型请求。

| 轮次 | 对比与修正 |
|---|---|
| 第一轮 `runtime/round1-*.png` | 检查默认、侧栏、grep、启动页。发现 EndOfBuffer 深色块、面包屑太细、重复 Lua 全局诊断、搜索窗过高 |
| 第二轮 `runtime/round2-*.png` | 统一 bg、收窄符号、LuaLS 单一全局诊断、降低搜索窗高度。继续修选中图标/匹配色、搜索遮罩导致侧栏不可见、无分支时的缓存回退 |
| 第三轮 `runtime/round3-*.png` | 检查无默认侧栏、过滤器和选中匹配色。像素检查发现非活动编辑区的空白行仍比正文浅，补充 EndOfBuffer 的 inactive 映射与回归；状态栏分开显示 error/warning 数量，去掉 hint 计数。修正后再次构建并截取根目录 `final-*.png` |

## 验证记录

重启前的截图、原始 probe 与性能日志已从仓库 `.work/claude-pause-2026-10-25/reboot-backup/old/r25` 恢复。旧 probe 保留原绝对路径作为历史证据；重启后全部验证使用上方新临时目录。重启前被终止的构建不计通过，重启后已重新完成全部构建。

最终包为实际 Home Manager Neovim 0.12.6：`/nix/store/pis7sd448x5icl8r665j27hc9nlca03w-neovim-0.12.6`，Kitty 配置为 `/nix/store/nqdvncb28ahcjd2fy0vnpfqr9525agbn-hm_kittykitty.conf`。最终代码包含 picker 动态标题居中、hover 拼写隔离，以及 Neogit namespace/EndOfBuffer 修正。29 个 Neovim 场景在最终包上全部重拍，探针均无加载错误；另重拍字体、tmux 字形网格、btop、Lazygit 和启动页。Kitty 字体日志确认 Regular/SemiBold/Italic/SemiBoldItalic 都启用 `calt cv01 zero`；Neogit 正文/空白区四点像素均为 deep `#181b20`。原始证据在 `final-manifest.json`、`runtime-reboot/`、`font-debug-audit.json`、`pixel-audit.json`。

| 命令/输出 | 结果 |
|---|---|
| `git diff --check` | 通过 |
| `nix fmt` | 通过 |
| `nix flake check --no-build --no-write-lock-file path:<filtered-source>` | 求值通过，44.13s |
| 全部30项 checks + normal/dev/HM Neovim + Kitty/tmux + toplevel | 单个 `nix build --no-link --no-write-lock-file --print-out-paths` 成功，117.66s |
| toplevel | `/nix/store/dzdv1kvm5fski9c19zlgxv9ccmki4zjx-nixos-system-nixos-btw-26.05.20261021.da6dc0e` |

完整检查使用只含 Git 跟踪源码及显式新增模板/文档的过滤快照 `source-canvas-final`，排除 `.work/`、运行状态和秘密明文。准确命令、退出码和输出路径在 `verification.json`、`all-checks-toplevel.log`、`final-packages.json`；不把求值写成构建。最终测量记录在构建后补齐，运行代码与过滤快照保持一致。构建未激活系统。

Neovim check 覆盖 overhaul/startup/completion/integration/workflow/fileops/lua_workspace/modern/interface/ai/native/codediff/panels_picker/panels_ai/panels_aux/panels_surface、9种语言 parser 样本、真实 LSP 集成、reducedMotion 与 wrapper 模式。LuaLS 检查含项目配置优先级和 managed-ancestor 控制；CodeDiff 使用临时 Git 仓库。全量键位扫描为 normal 206、visual 67、insert 20，重复及前缀冲突均为0。Rust/Go parser 通过，PATH 中无可选 LSP 时跳过 LSP，不全局安装。详细输出为 `neovim-check.log`。独立 reviewer 复核后无未关闭的实质缺陷。

| 启动模式 | 构建刚结束后 | 负载稳定后复测 | 两轮合并40次中位数 |
|---|---:|---:|---:|
| headless | 12.98ms | 12.42ms | 12.75ms |
| 真实 Kitty 首帧 | 28.70ms | 28.96ms | 28.93ms |
| 真实 Kitty + tmux 首帧 | 31.81ms | 29.82ms | 30.23ms |

两轮均为每组预热5次、实测20次，冷 Neovim 进程、热 OS/store cache；接通电源且平台为 performance，本轮未改变电源策略或其它用户进程。首次 tmux 超过预算，因此等待负载稳定后按相同方案完整复测，而非丢弃慢样本：首次 load 从10.19降到6.77，第二次从4.01到4.84。**稳定负载复测三组均≤30ms；tmux 跨负载合并仍为30.23ms，性能余量有限，不能宣称所有负载下都达标。** 两轮数据分别为 `startup-postbuild-first/report.json`、`startup-final/report.json`，完整合并数据为 `startup-pooled.json`。

GUI 数值来自 `--startuptime` 的 `first screen update`，不是从创建 Kitty 到合成器呈现的端到端时间；headless 使用 `NVIM STARTED`。启动页用 VimEnter 回调注入相同四条最近文件 fixture，计入时间，并由 RPC 核验图标、实际 config 路径、dashboard 与无错误。重启前 quiet 高负载测量保存在 `startup-before-reboot/`，performance 对照在 `startup-polish3/`、`startup-polish4/`；这些历史结果不与最终包复测混用。

## 追加精修 1–15

继续沿用 D1/D2，不恢复 Islands。`before-*.png` 是精修前已构建的 B+C 包；`polish1-*.png` 为首轮精修实拍；`final-*.png` 为最终精修。原始 PNG 未裁剪或重画；图集并排显示两端，并附界面审计截图。

| 项 | 最终处理 | 截图/测试 |
|---|---|---|
| 1 呼吸感 | Kitty `modify_font cell_height 108%`；字符宽度不变。真实 TUI 从 195×52 变为 195×49，像素网格受整数取整影响。没有用无效的 TUI `linespace` | `before-font.png` / `final-font.png`，`final-btop.png`、`final-font-tmux.png`、`final-font-lazygit.png` |
| 2 连字字形 | 四种 Maple Mono NF CN face 开启 `calt`、`cv01` 标准符号、`zero` 点状零。锁定字体 7.9 的 GSUB 确实含这三项；Kitty 实际选择 SemiBold/SemiBoldItalic，补齐这两种 selector 后再由字体日志核验，保留 Bold 选择器兼容其它 Fontconfig 结果；中文两列网格、斜体、Nerd Font 彩图标实拍核对 | 字形网格；Kitty Python config parser 与 shell-runtime 断言；[字体来源](https://github.com/subframe7536/maple-font/blob/v7/source/features/README.md) |
| 3 光标 | Normal block、Insert 25% beam、Replace 20% underline，颜色由 ModeChanged 更新；短 cursor trail 与 reducedMotion 保持 | `final-default.png`、`final-completion.png`；`interface.lua` |
| 4 选择/搜索 | 蓝色 14% 选区，brightFg 文字通过 WCAG AA；Search 淡底，IncSearch/CurSearch orange 底 deep 字；保留 `[3/14]` | `final-visual.png`、`final-search.png`；对比度与状态栏测试 |
| 5 配对/引用 | MatchParen 粗体下划线无底，LspReferenceText/Read/Write 极淡下划线 | `final-matchparen.png`；真实 highlight 断言 |
| 6 缩进 | 普通线接近 edge、当前 scope 略亮，只在当前窗口；关闭作用域动画 | `final-robot.png`；`interface.lua`、`panels_surface.lua` |
| 7 非活动 | bg 向黑混入 6%，`#1e2228` → `#1c2026`；空白行使用相同底色、无 `~` 噪声；只有活动窗口保留 CursorLine | `final-sidebar.png`、`final-ai.png`；inactive 文本对比度约 7.67:1 |
| 8 浮窗/补全 | rounded edge、muted 居中标题、左右一列虚拟留白；补全菜单 borderless/deep、紫 kind、右侧文档同风格。补齐 padding 几何：40字文档 42×1，限宽24时 24×2，无截尾 | `final-completion.png`、`final-hover.png`、`final-input.png`；真实 LuaLS 补全/hover，padding 回归 |
| 9 顶栏 | 彩色活动文件胶囊、准确 `+N`、状态小点、可点击项目；health/Grug FAR 等工具不混入文件标签 | `final-default.png`、`final-repository.png`；`overhaul.lua` 包含17种工具类型与溢出行为 |
| 10 状态栏 | 分色 `+N ~N -N`、`▲N ●N`、`● REC @q`、事件驱动 LSP 小转圈；其他字段保持 muted | `final-diff.png`；`workflow.lua`、`native.lua` 行为回归 |
| 11 Git/diff | 增删改底色在 bg 上混入 green/red/blue 12%，字内强调18%；CodeDiff 初始化与 ColorScheme 一致；gitsigns 细条同色相 | `before-diff.png` / `final-diff.png`；临时仓库 CodeDiff 回调测试 |
| 12 启动页 | 视觉居中略偏上，recent/projects 依窗口高度限制，底部单行；项目扫描保持首帧后调度 | `before-dashboard.png` / `final-dashboard.png`；dashboard 行为与首帧测量 |
| 13 通知 | 最新三条、3000ms、右上紧凑卡片、级别细条。隐藏旧通知后收拢空洞；不进 history 的通知也计入上限 | `before-notifications.png` / `final-notifications.png`；history=false 与重排回归 |
| 14 一致性 | 实开 help、checkhealth、Lazygit、Neogit、Aerial、Oil、Grug FAR、CodeCompanion、Claude 终端容器、terminal、quickfix、which-key、files/grep/select/input | `final-help/health/lazygit/neogit/aerial/oil/grug-far/ai/claude/terminal/quickfix/which-key/picker-files/grep/picker-select/input.png`，图集逐项列出 |
| 15 性能 | 原生大文件保护、宏执行/录制禁平滑动画。最终包稳定负载复测12.42/28.96/29.82ms；两轮合并 tmux 30.23ms，保留首次超预算结果与限制 | `startup-final/report.json`；`overhaul.lua`、锁定 Snacks scroll 源码与完整 checks |

### 常用界面审计

图集对应条目同时给出 `before-*` 与 `final-*`；只有新增控制场景（OC 模板、仓库、tmux）没有伪造旧图。

| 界面 | 处理方式 | 最终截图 |
|---|---|---|
| help | deep 工具窗口、muted 标题、从文档标签排除 | `final-help.png` |
| checkhealth | 同一工具窗口色板与标题，保留健康信息；本图只跑 Snacks | `final-health.png` |
| Lazygit | rounded edge、居中 Git 来源标题；使用仓库构建的 Lazygit 配置 | `final-lazygit.png` |
| Neogit | deep 状态面板、edge 细边框、muted 标题；显式覆盖私有高亮命名空间，避免链接环；按需打开 | `final-neogit.png` |
| Aerial | 按需符号岛改为普通工具窗口、无默认大纲 | `final-aerial.png` |
| Oil | deep 目录窗口及 Project 标题，不占文档标签 | `final-oil.png` |
| Grug FAR | 同一查找/替换工具表面，不占文档标签 | `final-grug-far.png` |
| CodeCompanion | 完整模型标题、规则摘要、低饱和 diff；真实 buffer + 本地 fixture | `final-ai.png` |
| Claude | 真实终端容器统一标题/色板；离线 fixture，不声称登录实测 | `final-claude.png` |
| Terminal | 底部按需终端、中英文及边框对齐 | `final-terminal.png` |
| Quickfix | 统一 Problems 标题、deep 底与单行条目 | `final-quickfix.png` |
| which-key | 安静底部菜单、键与分组克制强调 | `final-which-key.png` |
| Files / grep | 小型居中 picker、居中标题、彩色图标、蓝色选中条 | `final-picker-files.png`、`final-grep.png` |
| select / input | 统一选择列表与 rounded 输入框，保留原生确认/取消 | `final-picker-select.png`、`final-input.png` |
| completion / hover | 原生 LuaLS、borderless 菜单、右侧 Markdown 文档、rounded 居中来源标题 | `final-completion.png`、`final-hover.png` |

复核修掉了两个边界：浮窗虚拟留白导致的末行截尾，以及 managed Neovim 配置祖先目录的 `.luarc.json/jsonc` 优先级。LuaLS 现在先选择最近项目配置所在根，再考虑编辑器专用根；真实 LuaLS 控制包含 managed-ancestor 场景。AI 规则摘要从不可见的 conceal_lines+virt_lines 改为同一行 overlay，实拍确认可见，同时保留原文与请求 metadata。最后一轮检查移除了 Markdown hover 中 API 标识符的拼写红线；独立探针确认源窗口的拼写设置不受影响。Neogit 另有私有 namespace 的边框映射，以及 minimal 浮窗自动添加的重复空 `EndOfBuffer:` 映射；现在使用具体 deep/edge/muted 色，并将空白行显式映射到浮窗底色，避免亮边框与空白区色块。全局 EndOfBuffer 不再固定背景。独立 reviewer 复核后没有未关闭的实质缺陷。

最终截图及日志另备份于仓库 `.work/r25-final-evidence/`；图集内每个链接已核验存在。用户原始13–15图片在重启后未从备份找到，未伪造还原；D1/D2、精修前实拍及三轮截图均已保留。

限制：AI 聊天和 Claude 容器是标明无请求的本地 fixture，未登录或发送真实模型请求；没有修改用户 OpenComputers 项目。终端单元格不能绘制 CSS 的像素级圆角、字体字号和单像素边框，胶囊使用字体半圆、标题与正文共用终端字号，分隔线使用一列内的细线。用户桌面/显卡会话最终主观观感仍需启用配置后确认；本轮不激活系统。
