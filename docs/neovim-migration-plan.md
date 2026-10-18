# Neovim 原生 Lua + Nix 迁移计划

状态：**Lua + Nix 包及独立 `checks.neovim` 已构建通过；Home Manager 输出、host、treefmt、flake check 与最终桌面验证待主代理核验。** 当前依据是 2026-10-18 工作树、锁定 nixpkgs 与 Neovim 0.12.4；不据此宣称性能改善。Den 接线仍是后续工作。

## 顺序和已确认范围

按用户要求，先删除无用功能，再手工实现需要保留的功能，最后考虑新增、美化和结构整理。Nix 固定程序、插件、parser 和必要依赖；Lua 表达编辑行为。不预设移除插件必然提高性能。

本批按上一轮插件表 P 编号删除：

| 编号 | 删除项 | 结果 |
|---|---|---|
| P02 | blink-cmp-latex | 删除独立 LaTeX 命令补全源；服务端提供的补全仍由 Blink 展示。 |
| P03 | friendly-snippets | 删除通用片段集合；自定义 C++ `cpt` / `forr` / `vt`、原生片段展开/跳转保留。 |
| P12 | mini.nvim | 删除对齐和代码拆合扩展，撤掉其 `ga/gA/gS` 映射。 |
| P15 | clangd_extensions.nvim | 删除 AST、类型层次、符号信息 UI；保留 clangd 服务和原生 `<leader>lh` 源/头切换请求。 |
| P20 | Neogen | 删除注释模板生成及其映射。 |
| P29 | MCPHub | 删除编辑器面板、CodeCompanion MCPHub 扩展、专用 binary/input 和第二份 nixpkgs 接线；各独立 AI CLI 的 MCP 配置不受影响。 |
| P30 | TokyoNight | 当时删除外部主题后暂用内置 `habamax`；目前已由仓库内手写 One Dark Darker 取代，主背景 `#1f2329`。 |
| P31 | lz.n | 删除运行时加载器与所有触发声明，保留的插件直接加载，原 keys 映射迁到普通 keymaps。 |

Snacks 整个依赖移除，参考锁定源码，用 [自有 Lua](../config/nvim/lua/mayon/) 与 Nix 固定的插件和运行时接线保留需要的功能。不引入新的替代插件或自制加载器，也不清理旧 Scratch、主题偏好、会话或其他用户数据。

此前已删除 render-markdown、浏览器 Markdown 预览、Harpoon、Todo Comments、自动数学预览 helper、旧主题选择器和无调用方的 editor Mermaid CLI；不恢复这些功能。Undotree、Persistence、LuaSnip、ts-comments、Trouble、Fidget、Dial、Colorizer、vim-matchup 的外部插件已由先前的原生实现替代；同名 Nix 文件可能仍在，但不是对应插件声明。

## 第三批：只替换 Heirline 与 Navic

用户确认本批仅替换这两项，其余保留，避免扩大手工维护范围。实现位于 [statusline.lua](../config/nvim/lua/mayon/statusline.lua)、[tabline.lua](../config/nvim/lua/mayon/tabline.lua)、[breadcrumbs.lua](../config/nvim/lua/mayon/breadcrumbs.lua)，由 Lua 插件入口直接加载。

- 状态栏继续显示模式、文件/图标/标记、Git、诊断、LSP、宏/搜索、CodeCompanion 请求和 chat metadata，并按可用宽度减少可选信息。
- 标签栏保留同名路径区分、中文/百分号、未保存/只读标记、可见 buffer、左键切换、中键或关闭按钮安全关闭、溢出入口和原生 tab-page 切换/关闭。
- 面包屑从 documentSymbol 缓存查询当前符号路径；支持树状/平列表、LSP 编码换算、旧请求取消和过期响应保护。渲染不发送 LSP 请求，不用循环轮询。
- 语法 parser/query、UFO、Which-key、图标插件、格式化、Git、补全和 AI 插件保持当前选型；不新增替代插件。

## 手工实现的边界

| 模块 | 保留的入口和行为 | 与 Snacks 的区别 |
|---|---|---|
| [ui.lua](../config/nvim/lua/mayon/ui.lua) | `vim.ui.input/select` 圆角浮窗、默认输入、取消回调、格式化选项；`vim.notify` 分级通知、超时、替换、历史 | 选择器使用普通列表，不包含 Snacks 通用 picker 的模糊搜索/SQLite 排序。文件/内容搜索继续用 FzfLua。 |
| [files.lua](../config/nvim/lua/mayon/files.lua) | 文件树、目录入口、文件操作、保持布局的 buffer 关闭、LSP-aware 重命名、草稿、Lazygit、远程行链接 | 文件树不是完整通用 picker，不继承上游 explorer 的搜索/Git 聚合能力；草稿使用 `stdpath("data")/mayon-scratch` 独立目录，不自动转换或删除旧 `stdpath("data")/scratch` 中的 Snacks 草稿。 |
| [editor.lua](../config/nvim/lua/mayon/editor.lua) | 缩进/作用域线、同词高亮、状态列、作用域跳转、平滑滚动、1 MiB 大文件保护、Dim/Zen、编辑开关 | 作用域基于命名语法节点/缩进，缩进回退向上下各扫描最多 2000 行；滚动覆盖 Ctrl-D/U/F/B。Zen 为简洁专注布局；大文件阈值按字节，不承诺上游全部超长行启发式。Quickfile 由原生读取负责，不保留插件专属提前绘制机制。 |
| [image.lua](../config/nvim/lua/mayon/image.lua) | 普通图片预览与显式 PDF 首页预览；不可用时交桌面程序 | 不做 Markdown/TeX 文档内图像或公式自动渲染。直接打开 PDF 继续由现有自动命令交给桌面默认阅读器。 |

Noice 继续负责命令行、消息、悬停布局；关闭其 `vim.notify` 接管，消息走 `mini` 视图，应用通知由自有模块负责。状态栏、标签栏和 LSP 面包屑已由自有 Lua 实现，Which-key 继续展示键位。没有测量依据宣称新实现更省资源或更快。

## 保留功能与来源

| 功能 | 当前来源与保留内容 |
|---|---|
| 基础操作 | [core](../config/nvim/lua/mayon/core/)：选项、键位、autocmd、图标；撤销文件、剪贴板、分屏、保存、恢复光标、复制高亮、PDF 外开。 |
| 补全与片段 | [completion.lua](../config/nvim/lua/mayon/plugins/completion.lua)、[片段](../config/nvim/snippets/)：LSP/path/buffer、自定义 C++、文档、签名、CodeCompanion 来源；原生 snippet 跳转。 |
| 语法与编辑 | [editing.lua](../config/nvim/lua/mayon/plugins/editing.lua) 与 [queries](../config/nvim/after/queries/)：显式 parser 集合、Octave→MATLAB、文本对象、注释、自动括号、Surround、Flash、多光标、UFO 折叠及 Treesitter Context。 |
| 原生编辑辅助 | 内建撤销树、布尔切换、matchit/matchparen；原生 LSP documentColor 色块和 `<leader>uc`，不新增 CSS/Tailwind scanner。 |
| 文件和搜索 | 自有文件树/重命名、FzfLua、GrugFar、URL 打开模块。 |
| 会话 | [原生会话](../config/nvim/lua/mayon/features/sessions.lua)：目录/Git 分支、最近会话、未保存保护、mtime 并发保护、原子写入和旧文件名兼容。 |
| 语言工具 | [LSP](../config/nvim/lua/mayon/lsp/)、Conform、lint：现有服务、根识别、项目环境、原生 LSP 面包屑、MATLAB 超时后格式化路径、诊断/quickfix/进度。 |
| Git | [git.lua](../config/nvim/lua/mayon/plugins/git.lua)：Gitsigns、Diffview 和 [现有 fork](../pkgs/diffview-plus.nix)，自有 Lazygit 浮窗/远程链接入口。 |
| AI | [ai.lua](../config/nvim/lua/mayon/plugins/ai.lua)：DeepSeek chat/inline/cmd、Codex 默认 CLI、Grok/OpenCode 可选、历史、中文工作流、上下文和请求进度。 |
| 界面 | 自有 UI + Noice + 原生状态栏/标签栏 + 图标 + [高亮](../config/nvim/lua/mayon/ui/theme.lua)。 |

LSP/formatter/linter 继续从 Home profile/project PATH 解析。完整 TeX、Ghostscript、ImageMagick 保留；不将它们重新捆进 editor 包。Ruby/Python/Node/Perl remote-plugin providers 继续关闭。

## 核心键位

Leader 为空格；特殊 buffer 的局部映射优先，例如 chat 插入模式 Ctrl-S 发送。

| 操作 | 入口 |
|---|---|
| 保存/布局/buffer | Ctrl-S、Ctrl-h/j/k/l、Ctrl+方向键、Tab/Shift-Tab、`<leader>bd/ws/wv/q` |
| 补全 | Ctrl-Space/E、方向键、Tab/Shift-Tab、Ctrl-B/F 文档、Ctrl-K 签名 |
| 文件与搜索 | `<leader>e/ff/fg/fb/fr/fh/f./fR/sr/fu/fU`、`gx` |
| 编辑 | `gc/gcc`、`zR/zM/zK`、`[i/]i`、`<leader>m*`、`<leader>ub/uu` |
| LSP与诊断 | `gd/gD/grt/gi/K`、内建 `gr*`、`<leader>rn/ca/wd/lr/lf/ll/lh`、`[d/]d`、`<leader>xx/xX/xs/xl/xq` |
| 会话 | `<leader>ps/pl/pd` |
| Git | `]h/[h`、`<leader>gs/gr/gS/gR/gp/gb/gB/gd/gq/gg/go/gD/gH/gC` |
| AI | `<leader>aa/ap/av/ai/at/aT/ah` 和现有上下文/工作流键；chat 内 `<leader>ar` |
| 界面 | `<leader>us/uS` 草稿；`uz/ud` 专注/Dim；`un` 通知历史；`uh/uD/ue` Noice 消息入口；`uw/up/ur/ux/ui/ut/uc` 编辑开关 |
| 图片 | `:ImagePreview [path]`；普通图片文件入口由 image 模块处理 |
| 格式化控制 | `<leader>lf`、`:FormatDisable`、`:FormatEnable` |

撤掉的扩展键包括 `ga/gA/gS`、`<leader>la/lt/li`、Neogen 的映射、`<leader>am`；原生默认键可能仍有自己的含义。不重新利用已经退休的 `<leader>fs`。

## 当前 Lua + Nix 入口与使用方式

Lua 配置位于 `config/nvim/`，包装和固定依赖位于 `pkgs/neovim/`，flake 输出位于 `flake/neovim.nix`。Home Manager 已切到 `pkgs/neovim`，旧 Nixvim input 与模块树已退出，XDG init 指向同一份 `config/nvim/init.lua`。入口内有全局幂等保护，避免 wrapper 和 XDG init 重复执行；最终 Home Manager 求值确认仅安装这一份编辑器，XDG init 与其配置目录同源。

```sh
nix run .#neovim
NVIM_CONFIG_DIR="$PWD/config/nvim" nix run .#neovim-dev
```

普通包使用 store 中固定的配置树，忽略 `NVIM_CONFIG_DIR`；显式 dev 包允许该变量覆盖配置目录，便于工作树编辑。两者共用锁定的插件和 parser 依赖。包保留 20 个直接插件、递归运行时依赖去重后的闭包、16 个语言服务和 32 个显式 Tree-sitter grammar；构建与运行检查结果见下表。

`config/nvim/` 包含 `init.lua`、`lua/mayon/{core,features,lsp,plugins,ui}`、`after/queries/`、主题、片段和可重跑 Lua 检查。`pkgs/neovim/{default,plugins,parsers}.nix` 固定 wrapper、插件和 parser 接线；`flake/neovim.nix` 暴露普通与开发调试入口。Nix 管理可复现的程序、插件、parser/query 资源及必要基础工具；LSP、formatter、linter 和项目编译器继续从 Home profile 或项目环境 PATH 获取。

- wrapper 使用锁定 stable 的 `wrapNeovimUnstable pkgs.neovim-unwrapped` API；名称不表示切到 unstable 包集合，也不使用 deprecated `makeNeovimConfig`。
- 插件直接加载，不恢复 lz.n 或另造加载器；递归依赖不应重新引入已删插件。Diffview fork 与 CodeCompanion history override 保持原依赖约束。
- One Dark Darker 是仓库内手写主题，主背景为 `#1f2329`；当前已接入配置，不添加主题插件。没有测量依据宣称迁移或删插件改善性能。
- Ruby/Python/Node/Perl remote hosts 关闭；完整 TeX/JDK、语言服务与格式化工具不捆进 editor 包。额外包只提供 baseline editor tools。

## 迁移验收状态

| 项目 | 当前记录 |
|---|---|
| 基线与回退 | 保存了可恢复 tar、diff、manifest 与 runtime.json 快照；迁移前后用户状态数据不由包管理器清理。 |
| Neovim 包专项检查 | 普通/dev 包和 `checks.neovim` 已构建通过；检查包含完整 startup、真实 Blink C++ snippet 加载/展开/跳转，以及 native、statusline、tabline、breadcrumbs、LSP 样本。 |
| flake 与主机输出 | `nix fmt`、`nix flake check --no-build --no-write-lock-file`、treefmt、`checks.neovim` 与完整 host toplevel 构建通过；未切换系统。裁剪锁图只移除 Nixvim 及孤立 systems 节点，其余锁定 revision/hash 不变。 |
| Home Manager 与桌面入口 | HM 求值仅安装同一普通包、链接同源 init；新旧 `nvim.desktop` 入口无功能差异。实际验证普通包固定路径、dev 覆盖、`--clean` 和显式 XDG `-u`；桌面菜单点击未实测。 |
| UI/交互与性能 | 隔离 PTY 验证输入/选择、FzfLua 文件搜索、会话保存与恢复。完整 dev 包下真实 LuaLS 符号面包屑随光标变化，CSSLS 对未保存修改发布诊断，Conform 调用 StyLua 格式化均通过。未实测本轮 Kitty/tmux 图像、MATLAB、AI 网络请求或桌面字体观感；没有性能结论。 |

不为验证改用户项目、不发真实付费 AI 请求、不输出密钥、不删除用户状态。构建本身不会应用配置或替代真实交互验收。

单独运行检查：`nix build --no-link .#checks.x86_64-linux.neovim`。检查入口在 Lua 内将失败转为非零退出，并用故意失败的断言验证了退出码为 1。该检查中的 LSP 样本是配置断言；本轮真实语言服务与 PTY 结果来自另行执行的隔离集成测试，不混同为构建覆盖。开发包依赖已确定的 Home profile / 项目 PATH，空环境下不会自动下载语言服务。

基线保存于用户状态目录的 `nix-dotfiles/baselines/neovim-lua-20261018T013041Z`，含迁移前工作树、索引差异、内容校验、生成入口和运行报告；没有清理现有会话、草稿与插件历史。

## 接口依据

- 仓库：[安装入口](../modules/home/programs/dev/nvim.nix)、[包定义](../pkgs/neovim/default.nix)、[插件](../pkgs/neovim/plugins.nix)、[解析器](../pkgs/neovim/parsers.nix)、[flake 输出](../flake/neovim.nix)、[工具链](../modules/home/programs/dev/toolchain.nix)。
- [锁定 nixpkgs wrapper](https://github.com/NixOS/nixpkgs/blob/7993f34ee47e28a3d607a525aadc6c94b73be728/pkgs/applications/editors/neovim/wrapper.nix)、[utils](https://github.com/NixOS/nixpkgs/blob/7993f34ee47e28a3d607a525aadc6c94b73be728/pkgs/applications/editors/neovim/utils.nix)：实施以本地锁定源码为准。
- 手工实现参考锁定 Snacks 2.31.0 对应的未编译源码；源码仅用于行为核对，不再作为运行依赖。
- [Neovim 启动文档](https://neovim.io/doc/user/starting/)：实际 wrapper 和本机版本帮助优先。

手写主题的调色板参考 [One Dark 官方 darker palette](https://github.com/navarasu/onedark.nvim/blob/master/lua/onedark/palette.lua)，保留 [MIT 许可](../config/nvim/colors/ONEDARK-LICENSE)。主编辑区、浮窗和状态栏分层，Treesitter Context 保持编辑区背景。
