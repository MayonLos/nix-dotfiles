# Neovim 第六轮完全重构

2026-10-24 第十轮后续：Python 使用 basedpyright，新增 Taplo；启动页字形、渐变与路径展示已修正。Lua LSP 对比与本轮构建证据见[软件替换记录](history/software-swap-2026-10-24.md)。下文此前的首文件实测保留原版本语境。

状态：2026-10-24，重构已实现并完成构建与隔离验证；本轮**尚未应用**，没有执行 `sudo`、
`nixos-rebuild`、Git stage/commit/push 或系统切换。完整 health 仍有两个明确限制，见下文。
此前实施与应用记录及本轮执行细节见[历史归档](history/neovim-rebuild-2026-10-24.md)。

用户授权完整重做 Neovim，可调整功能与交互。实现保持 Nix 固定插件、Den 生成的语言和
palette 数据，以及 One Dark Darker（`#1f2329`）；Mango 仍为桌面默认。Home Manager
配置随 NixOS 重建，没有独立 switch。

## 架构与加载

`config/init.lua` 只调用 bootstrap。配置分为 `mayon.config`（选项、键位、自动命令与
加载器）、`mayon.plugins`（按领域返回 lz.n specs）、`mayon.ui`、`mayon.features` 和
`mayon.lsp`。Nix 固定插件及完整依赖闭包；启动插件为 One Dark、Heirline、Snacks、lz.n
和 nvim-web-devicons。其余插件与传递依赖列为 optional，由生成的依赖图在 lz.n 命中
`event`、`cmd`、`keys` 或 `ft` 后按序 `packadd`。不在运行时下载插件。

普通 picker、项目树、dashboard、LazyGit 与图片入口共用 Snacks。保留 nvim-navic，状态栏
只在宽屏使用其符号；导航模块按 `LspAttach` 懒加载并主动连接已附着客户端，因为 lz.n
不会重放无 augroup 的已发生事件。`fzf-lua` 已删除。`nvim-ufo` 已删除，折叠改由 Neovim
0.12 原生 LSP `foldingRange` 优先、Tree-sitter 回退，折叠文本显示首行和行数；`zR/zM/zc/zo`
使用原生操作。

锁定 Neovim 0.12.4 已将旧 `vim._extui` 迁至 `vim._core.ui2`。其 runtime 文档仍明确标为
experimental；公开选项控制消息路由、窗口高度和超时，`check_targets()` 将命令行创建为
`relative=laststatus`、`col=0`、全宽且无边框，没有居中圆角弹框的公开几何配置。实现该布局
需要改写私有窗口行为，因此本轮保留 Noice，由 `User MayonVeryLazy` 或其命令懒加载。命令框继续位于底部居中，消息由 Noice 接管并延后初始化。LSP、格式化、
lint、Treesitter、Blink、Flash、文本对象、多光标、surround、autopairs、Markdown、Trouble、
Diffview、CodeCompanion、会话、草稿、URL、公式预览、C++ snippets 和项目 PATH 保留；AI、
语言服务及编辑器扩展按领域懒加载。

新增插件为 `lz.n`、`oil.nvim`、`yazi.nvim`、`nvim-dap`、`nvim-dap-view`、
`nvim-dap-virtual-text`、`overseer.nvim`、`todo-comments.nvim`、`rainbow-delimiters.nvim`、
`nvim-colorizer.lua`、`tiny-inline-diagnostic.nvim`、`satellite.nvim`、`incline.nvim` 和
`smear-cursor.nvim`。删除 `fzf-lua` 与 `nvim-ufo`，并移除不再需要的传递依赖。

```text
lua/mayon/
  config/    bootstrap、options、keymaps、autocmds、loader
  plugins/   按领域返回 lz.n spec 列表
  ui/        theme、dashboard、statusline、tabline、breadcrumbs、icons、noice、text
  features/  fileops、oil、folds、sessions、scratch、urls、math_preview、AI/补全小组件
  lsp/       原生 LSP 配置、服务器适配、进度与项目 PATH
```

## 文件安全与用户数据

Snacks Explorer 提供侧栏，Oil 通过 `-` 打开可编辑父目录缓冲，Yazi 通过 `<leader>fy` 打开
浮窗。Oil 使用回收站删除并保留简单编辑确认；fileops 接管本地创建、移动、复制和删除的
安全检查。目标存在、是符号链接或冲突时拒绝创建/覆盖；文件复制走自有 exclusive-copy，
避免锁定 Oil 源码 `undo-copy` 路径的潜在覆盖问题。回收站只允许安全移回，永久 purge 被
拒绝；Oil 的 LSP 文件操作关闭，以免与 fileops 重复应用 workspace edit。普通文件源 undo 不会随创建、移动、复制或删除迁移或删除；复制失败时保留已创建的部分目标，便于检查，不自动清除它们。

undo、会话、草稿、AI 对话历史、shada、项目、模型、凭据及其他 Neovim 用户数据保留原路径
与格式，不因配置重排而清理或转换。配置重组不代表数据迁移。

## 键位

which-key 分组标签统一为英文：Files、Search、Git、Code、Debug、Run、AI、UI、Diagnostics、
Windows、Buffers；LSP、Sessions、Docs、Multiple cursors 和 CLI agents 继续保留。

| 键位 | 行为 |
|---|---|
| `<leader>ff` / `fg` / `fb` / `fr` / `fh` | Snacks 文件、grep、buffers、最近文件、帮助 picker；原入口保留 |
| `<leader>fs` / `fS` / `fd` / `fk` | 文档符号、工作区符号、诊断、键位 picker |
| `<leader>f:` / `f/` / `fp` / `f.` | 命令历史、恢复上次 picker、项目、当前 buffer 行 |
| `<leader>fy` / `-` / `<leader>e` | Yazi 浮窗 / Oil 父目录编辑缓冲 / Snacks Explorer 侧栏 |
| `<leader>gg` | Snacks LazyGit，保留 Git 入口 |
| `<leader>st` / `<leader>xt`；`[t` / `]t` | Snacks Todo grep / 上一个、下一个 TODO |
| `<leader>sr` | GrugFar 搜索替换，仍保留入口 |
| `<F5>` / `<F10>` / `<F11>` / `<F12>` | DAP 继续 / 跨过 / 进入 / 跳出 |
| `<leader>db` / `dB` / `dc` | 切换断点 / 条件断点 / 启动或继续 |
| `<leader>di` / `do` / `dO` | 进入 / 跨过 / 跳出 |
| `<leader>dr` / `dl` / `dt` / `dv` | REPL / 上次调试 / 终止 / 调试视图 |
| `<leader>rr` / `rt` / `ra` / `rc` | 选择任务 / 任务列表 / 任务动作 / CMake 构建 |
| `<leader>rn` | 保留 LSP 符号重命名；`<leader>fR` 用于文件重命名 |
| `zK` | 原自定义上下文入口改为原生 `zo` 打开折叠 |

`<leader>` 的文件搜索、grep、buffers、最近文件、符号、诊断、Git、帮助、keymaps、命令历史、
项目和 picker 恢复现统一使用 Snacks；此前 fzf-lua 同功能入口迁移到 Snacks，常用 `ff/fg`
等键位保持。新键和保留键的当前完整定义以
[`navigation.lua`](../aspects/dev/neovim/config/lua/mayon/plugins/navigation.lua)、
[`keymaps.lua`](../aspects/dev/neovim/config/lua/mayon/config/keymaps.lua) 与领域插件为准。

| 旧入口 / 行为 | 本轮行为 |
|---|---|
| fzf-lua 的 `ff/fg/fb/fr/fh` 等搜索入口 | 绑定不变，底层统一换成 Snacks picker |
| 原 `zK` 自定义折叠上下文 | `zK` 明确映射到原生 `zo` |
| 原 `<leader>rn` 符号重命名 | 保留；文件重命名单独使用 `<leader>fR` |
| 没有 Oil/Yazi 的专用导航键 | 新增 `-`、`<leader>fy`；`<leader>e` 继续打开 Explorer |
| 尚无统一的 DAP/任务入口 | 新增 F 键、`<leader>d*` 与 `<leader>r*` 工作流 |

## 外观与功能扩展

One Dark Darker 和 Den palette 仍是唯一颜色来源。状态栏按 120/80/40 列收缩，包含模式、
Git、相对路径、诊断、LSP、AI、文件类型、非 UTF-8 编码和位置；标签栏保留重名消歧、CJK
截断、未保存标记和关闭行为。折叠、标记列、浮窗和新插件的高亮由集中 theme adapter 管理。

dashboard 使用蓝青 MAYON 标题、文件/搜索/项目/会话/配置快捷入口及配置初始化时长（从 bootstrap 计时，不冒充进程总启动时间）。Oil/Yazi、
LazyGit/Diffview、DAP（lldb-dap 与 Python debugpy 路径来自 Nix 注入）、Overseer、
todo-comments、rainbow-delimiters、Colorizer、tiny-inline-diagnostic、Satellite 与 Incline
按触发条件加载。smear-cursor 在 reducedMotion 为假时启用，关闭插入动画和跨 buffer 拖尾，
保留克制的相邻行动画。Kitty 是否闪烁尚未实机确认，不能据猜测宣称已验证；若实机出现问题，
再禁用这一动画模块。Incline 单窗口隐藏；Colorizer 仅作用于 CSS/HTML/Lua/Nix。

## 验证与性能

本轮没有修改 `flake.lock`。`git diff --check`、`nix fmt`、锁定 StyLua 检查、
`nix flake check --no-build --no-write-lock-file` 均实际执行；后者只证明求值。
完整 flake check 已构建当前 x86_64-linux 的全部 18 个命名 checks，包括 Neovim、treefmt、
editing-composition 和系统/桌面组合。普通 Neovim、`neovim-dev` 和 NixOS toplevel 也已构建，
没有执行激活。命令、源码快照边界和最终 store 路径记录在历史文件。

`checks.neovim` 实际执行 startup、completion、integration、workflow、fileops、lua_workspace、
modern、interface、五语言首次打开、真实 CSS 未保存诊断、三种 wrapper 及故意失败 runner。
覆盖 optional 启动隔离和触发、Snacks picker 入口与真实 finder、dashboard 渲染、LSP/TS 折叠、
Oil 的真实回收站/dirty/覆盖/symlink/只读目录/copy 防递归/源 undo 保护、DAP 适配器路径、
全部插件 setup、重载主题和 40/60/80/100/120/180 列 UI。
Lua/C++/Python/Markdown/Nix 首文件分别实际附着 LuaLS/clangd/pyright/marksman/nixd；
Treesitter、Navic、格式化和诊断模块加载无错误。Markdown 没有配置外部 formatter，继续使用
既有通用空白整理。AI 未进行联网模型请求，DAP 未执行真实项目调试。

最终启动样本（最终普通包，三次独立 HOME/XDG，旧/新交替运行）：

| 包 | 三次 NVIM STARTED（ms） | 中位数（ms） |
|---|---|---:|
| 旧普通包 | 75.766 / 74.574 / 75.159 | 75.159 |
| 最终普通包 | 26.364 / 26.363 / 26.147 | 26.363 |

中位数降低约 64.9%，满足 ≤35ms 的验收目标。首次开发包样本 24.742 / 23.845 /
23.897ms（中位数 23.897ms）只保留为过程记录，不与最终普通包混作一组。

Lua 小项目的 `--startuptime` 为 **126.048 ms**（NVIM STARTED）；独立 LspAttach 探针从
`--cmd` 执行点计为 **112.757 ms**。两者起点不同，attach 在启动期间已发生，不将其误写为
启动之后额外等待该时长。该记录是小 fixture 的一次样本。

这是同机有限样例；没有清空操作系统文件缓存，不代表所有工程或真实界面性能。

完整 headless `:checkhealth` 初始化 UI 生命周期和所有可选插件后仍有 **2 ERROR**：
缺少可选 Mermaid 渲染命令 `mmdc`；无物理终端的 headless 会话无法协商 Kitty 图形协议。
因此**未达到完整 health 零 ERROR 验收**。单独排除 Snacks 的可选媒体检查后，其余已加载
插件和核心 LSP/provider/Tree-sitter 检查为 0 ERROR；该分项结果不替代完整扫描。
warning 还包括未安装的可选任务工具、缺少项目模板、mini.icons 提示（已用 devicons）和版本提示。
公式的实际显示、Kitty 图像能力、smear-cursor、dashboard/分屏 Incline、补全/命令框与
40/80/120 列实际观感仍待实机视觉验收。构建、headless 与小 fixture 不能替代这些检查。
