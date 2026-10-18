# 仓库全面重构执行计划

本文件保留已确认的软件取舍及各历史批次证据；不是当前代码入口说明。Den 整仓迁移已实现，当前结构见 [架构](architecture-design.md)，本轮重新执行的验证与回退点见 [实施记录](den-execution.md)。旧 Nixvim 名称、store 路径和早期样本结果只对应当时提交，不能代替当前源码或检查。

软件选型已结束：保留 VS Code、IDEA/PyCharm/CLion、原生 Lua Neovim、Mango/Noctalia、Kitty/tmux 及下文确定的全部软件。新增 Xarchiver/Okular，未选择的条件推荐不纳入本轮。完整功能已迁入 `aspects/`，inventory 只接真实笔记本，旧兼容入口与测试子 flake 已移除。没有 switch/test、部署服务器或删除用户数据；运行态仍可能来自旧 generation。

## Neovim Lua + Nix 入口迁移（2026-10-18）

- Home Manager 安装编辑器功能生成的固定 Neovim 包；配置迁入 `aspects/editing/neovim/config/`，包定义和固定依赖位于 `aspects/editing/neovim/`，flake 输出位于 `nix/neovim.nix`。旧 Nixvim input 与模块树已退出。
- 普通与开发入口分别是 `nix run .#neovim` 和 `NVIM_CONFIG_DIR="$PWD/aspects/editing/neovim/config" nix run .#neovim-dev`。普通包使用固定 store 配置，只有显式 dev 包允许环境变量覆盖配置路径。
- 当前包固定 20 个直接插件、16 个语言服务、32 个 Tree-sitter grammar；parser/query 资源继续由 Nix 提供，历史 Nixvim 配置的 injections 行为由 `aspects/editing/neovim/config/after/queries/` 保留。
- 手写 One Dark Darker 已接入，主背景 `#1f2329`；未做性能对比，不作更快或更省资源的结论。
- 普通/dev 包及 `checks.neovim` 已构建通过；专项检查包含完整 startup、Blink C++ snippet 加载/展开/跳转和 native、statusline、tabline、breadcrumbs、LSP 样本。`nix fmt`、flake check 求值、treefmt、host toplevel 与最终 HM 输出检查均通过。
- 锁定 Neovim 的 `nvim.desktop` 在旧/新包中无功能差异；HM 最终求值确认只有这一份编辑器和同源 init；实际桌面菜单启动未测。基线快照含 tar、diff、manifest 与 runtime.json，可用于审查和恢复；不在此重复个人状态目录路径。
- 完整 dev 入口下真实 LuaLS 符号路径变化、CSSLS 未保存诊断、StyLua 格式化通过；PTY 验证输入/选择、FzfLua、会话保存/恢复通过。普通包固定路径、dev 覆盖、`--clean` 和显式 XDG `-u` 入口通过；本轮未测 Kitty/tmux 图像、MATLAB、AI 网络请求和桌面字体。
- 详细保留范围、手工实现边界、键位和验证限制见 [Neovim 迁移计划](neovim-migration-plan.md)。

## Neovim 第三批：原生状态栏、标签栏与面包屑（2026-10-18）

状态：**已修改并完成下列验证，未切换系统**。用户明确只替换 Heirline、nvim-navic，其余插件保留。

- 新增 `nixvim/lua/mayon/{statusline,tabline,breadcrumbs}.lua` 和 `appearance/bars.nix`，删除两个旧插件模块及声明。
- 原生 statusline/tabline 保留当前模式、Git/诊断/LSP/AI 状态、buffer 标记、同名路径消歧、中文宽度、安全关闭与 tab-page 操作；符号路径由原生 LSP 缓存提供。
- 图标 kind 表由同一份 Nix 数据生成给 Blink 和面包屑，文件图标继续复用已保留的 web-devicons；没有增加新插件或变更 flake 输入。
- 新增三个可重跑样本 `nixvim/tests/{statusline,tabline,breadcrumbs}.lua`，分别验证布局/状态、buffer/tab 操作与 LSP 符号缓存。

验证结果：

- `nix fmt`、`nix flake check --no-build --no-write-lock-file`、treefmt 检查输出与完整主机 toplevel 构建通过。新增 Lua 与测试的 Stylua、差异空白和本地文档链接检查通过。
- 直接插件列表为 20 项，Heirline/Navic 不在运行时闭包；其余保留插件匹配预期清单，没有新增插件或更新输入。
- 隔离 XDG 下三个专项样本及此前的文件保护测试通过。覆盖百分号/中文宽度、窄窗/全局与非活动窗口、并发 AI 请求/聊天 metadata、同名文件、关闭取消、符号树/平列表、编码、过期响应和重命名 URI。
- 最终包 `/nix/store/h6cx1ssqxkqzfzzfmkhyd55vxzzk9pyj-nixvim` 冷启动、实际 devicons、生成 kind 表、CodeCompanion 设置与颜色重载检查通过。
- 真实 Lua LS 返回 `outer › inner` 符号路径并显示到状态栏。首次冷启动中 runtime 库仍在预加载，超过 12 秒测试阈值；后续两次样本通过，未借此修改既有 Lua LS 预加载配置或宣称性能改善。
- PTY/TUI 通过实际鼠标事件验证标签左键切换、中键关闭、关闭按钮的未保存确认取消、原生 tab 页切换/关闭，且待保存内容保留。独立复核发现的非活动背景覆盖、重命名旧 URI 缓存问题均已修复并加入测试。

没有切换系统、发起真实 AI 请求或进行性能对比；桌面字体和最终 One Dark Darker 视觉设计仍属后续阶段。本批范围只替换两个插件。


## Neovim 第二批删除与手工实现（2026-10-18）

状态：**已修改并完成下列验证，未切换系统**。用户确认删除 P02/P03/P12/P15/P20/P29/P30/P31，并选择参考 Snacks 源码手工实现全部原有启用功能。

- 删除 blink-cmp-latex、friendly-snippets、mini.nvim、clangd_extensions.nvim、Neogen、MCPHub、TokyoNight、lz.n；保留自定义 C++ 片段和原生 clangd 源/头切换。撤掉被删扩展的映射。
- 删除 Snacks 运行依赖，显式加载 `nixvim/lua/mayon/{ui,files,editor,image}.lua`。输入/选择、通知/历史、文件树/目录启动、重命名、buffer 关闭、草稿、Git 入口、缩进/同词/作用域、状态列、滚动、Bigfile、Dim/Zen、编辑开关与图片预览由自有 Lua 实现。
- 保留插件直接加载，迁出原 loader 内的按键；不另造加载器。主题暂用内置 habamax，固定 One Dark Darker 留后续。
- 移除 mcp-hub 输入和只供它使用的节点、编辑器第二份 nixpkgs；按依赖路径核对锁图，其余输入的 revision/hash 未变（Nix 可重新编号同名节点）。
- Noice 保留命令/消息界面，关闭其通知接管；原生通知只有一个写入者。Heirline 保留。

范围、键位、能力简化与后续迁移见 [Neovim 计划](neovim-migration-plan.md)。锁定源码行为核对与隔离测试分开记录，不将 headless 或协议样本当作真实 Kitty 图像验收。`nixvim/tests/native.lua` 为文件数据保护、状态恢复和 headless UI 的可重跑检查。

本批验证：

- `nix fmt`、`nix flake check --no-build --no-write-lock-file`、treefmt 检查输出与完整主机 toplevel 构建通过；四个 Lua 模块和测试脚本的 Stylua 检查、文档本地链接与差异空白检查通过。
- 求值的外部直接插件数从 31 降至 22（不计生成的 nvim-config 与递归依赖）；新 editor 运行时闭包中无这九项插件，锁图只裁剪 MCPHub 孤立依赖，其余 revision/hash 不变。
- 最终 editor `/nix/store/8725w14r7fw6shgn44gxcgh4wkvdxmf2-nixvim` 在隔离 XDG 下通过空启动、目录参数、1 MiB 以上 Lua 文件和实际 StyLua 格式化。CodeCompanion 中文设置/历史、迁出的命令与快捷键、自定义片段 manifest 和 habamax 基线检查通过。
- 同一新包在 PTY/TUI 下验证中文默认值加输入、选择第二项、Normal 模式恢复、合并清除 Noice 消息与自有通知；独立 TUI 样本还验证 Insert 恢复、取消只回调一次、通知替换/超时/历史。无真实 AI 网络请求。
- 可重跑文件回归验证取消/保存关闭保留分屏、目录重命名后未保存内容、拒绝覆盖已有文件和悬空符号链接、首次保存保护外部改动；另测连续两次未保存重命名、首次保存的 BufWritePre/Post 和草稿自动保存。
- 编辑样本验证作用域、滚动计数/中断、mark/诊断/折叠/Git 分栏、两个窗口的高亮隔离、颜色重载、Zen 恢复；大文件在插件 FileType 处理后仍关闭语法、Treesitter 和 Blink，且未停止共享 LSP client。
- 图片样本调用真实 kitten 并捕获协议、用真实 ImageMagick 转换 PDF 首页，替代 `/dev/tty` 写入以核对图像数据、颜色和清理；另测原 PDF fallback、有效 tmux pane 的透传选项。协议先发送 virtual placement，再绘制 Unicode 占位符，并保存/恢复终端光标。

未做性能对比、所有语言服务回归、真实 Kitty/tmux 几何显示或鼠标折叠点击；这些不能由构建或 PTY 样本替代。系统尚未切换，用户状态与旧草稿未清理。


## Neovim 第一批前置删减与原生替换（历史验证，2026-10-18）

状态：**已修改并验证，未切换系统**。先在现有 Nixvim 入口完成删减和原生替换，不提前搭新框架或增加功能。

| 项目 | 当前实现与边界 |
|---|---|
| 自动公式预览 | 删除 `math_preview.lua`、启动调用和专用转换设置；文档图像/数学自动渲染关闭，普通图片预览保留。 |
| Mermaid CLI | 文档渲染关闭后，仓库没有其他 editor 调用方，从 editor extraPackages 移除；不清理缓存，不因此删除其他应用的 Chromium。 |
| 主题选择 | 删除 `nixvim/theme.nix`、导入和 `<leader>fs` 映射，不再读写 Tokyo Night 风格偏好。外部 TokyoNight 也按最新选择删除，暂用内置 habamax；One Dark Darker 留到后续整理，旧偏好文件保留。 |
| vim-matchup | 移除外部插件，显式加载内建 matchit；matchparen 负责括号高亮。保留 `%` 原生结构匹配，不保留 matchup 离屏 popup、专有 surround/transmute；独立 nvim-surround 不变。 |
| Colorizer | 移除外部插件，依靠内建 documentColor，`<leader>uc` 切换当前 buffer。覆盖以服务端实际能力为准，无颜色 LSP 的文件、普通 JS/TS 和 Tailwind 类名不再由独立 scanner 补齐。 |
| Heirline | 首批保留。完整原生 statusline/tabline 需独立迁移活跃组件、同名路径消歧、中文宽度、点击、布局和刷新事件，列为后续原生替换批次。 |
| 共享文档工具 | 完整 TeX、Ghostscript、ImageMagick 保留；更新 LaTeX/Kitty 注释，避免把已删公式流程继续写成当前依赖。 |

验证：

- treefmt 和完整主机 toplevel 构建通过。editor 配置求值断言通过：两个外部插件关闭、math helper 不再安装、Mermaid CLI 不在 extraPackages，普通图片启用、自动文档/公式渲染关闭，Ruby/Python remote providers 未恢复。
- 新构建的 `/nix/store/7jlwc04cp8acvhivb0vm61dnrms3xnz1-nixvim` 使用隔离 XDG 与新 Home profile PATH 冷启动通过；原生 matchit/matchparen 已加载，无 Colorizer 命令、matchup 标记、math helper/augroup 或旧主题选择映射。
- 在隔离数据目录预置旧风格 `day` 后，仍固定 night，证明旧偏好不再影响启动；未读写用户实际偏好。
- 临时 CSS 项目启动真实 cssls 并确认 documentColor 能力；hex/rgb 原生色块、当前 buffer 开关及 ColorScheme 重载后恢复均通过。headless 检查显式 redraw 触发原生 decoration provider，不冒充 Kitty 显示回归。
- 独立 runtime 临时样本验证 HTML 嵌套标签、Lua if/end 的 `%` 跳转和 matchparen 高亮；会话、补全、Git/AI 等未借本次删项重写。

没有做性能对比、Kitty/tmux 图像显示或所有 filetype 回归；未切换系统或清理用户数据。`colorizer.nix`、`vim-matchup.nix` 暂承载原生实现，命名整理留到最后，不能据旧文件名判断外部插件仍安装。

## 软件选型收尾：Xarchiver 与 Okular（2026-10-18）

状态：**已修改并验证，未切换系统**。用户选择这两个新增项，软件选型阶段结束；Xournal++ 未选，不添加。

- `aspects/default.nix` 添加 stable Xarchiver 0.5.4.26 和 Okular 26.04.3。
- `aspects/media/images.nix` 使用当前锁定 Home Manager 的 `xdg.mimeApps.associations.added` 将 `org.kde.okular.desktop` 加入 PDF 可选打开方式；Zathura 继续作为默认，Zotero 和编辑器 PDF 外开行为不被替换。
- `aspects/file-manager/host.nix` 为 archive plugin 做局部 override。锁定插件只从编译进自身输出的 libexec 路径查找 `.tap`，不会自动找到另一个 store 输出的 Xarchiver helper；因此在插件内创建 wrapper，调用 Xarchiver 已经由 wrapGAppsHook3 包装过的 helper，同时提供 GUI 的固定 PATH。不把已经是 ELF 的 helper 当文本修改，也不依赖 Thunar 是否继承用户 profile PATH。
- 不额外接管全部归档 MIME。插件可按 Xarchiver desktop 声明发现处理程序；保留 Thunar 自定义菜单、GVFS 与其他插件。

验证：

- treefmt 与主机 `system.build.toplevel` 构建通过；包/MIME/插件路径求值通过。
- 新 Home profile `/nix/store/cmlyxgspmg6idlmkmlxhk52xl7lpm1mk-home-manager-path` 包含两个程序及其 desktop 文件，Xournal++ 不在清单；PDF 默认/可选关联断言通过。
- 插件二进制内的固定 libexec 路径与新增 helper 相符；helper 可执行、包含固定 GUI PATH，并能正确返回 unsupported-action 分支。没有创建/解包用户文件。
- 新包的 `xarchiver --version`、`okular --version` 通过；Okular 版本检查使用 offscreen 平台。
- 文档本地链接、空白检查通过；Neovim 计划做过分工只读复核，顺序和 wrapper 调用说明已修正。

没有切换系统，也未点击真实 Thunar 菜单或做 PDF 批注保存回归。上述检查不等同于新桌面关联已经应用；应用后再验证实际操作。该软件批次当时只盘点和规划 Neovim；后来已实施前置删减/原生替换（见本文开头），该批次当时尚未迁移 Lua + Nix 入口；入口现已完成迁移与验证，依赖未顺带升级。

## 音频与剪贴板精简（2026-10-18）

用户确认处理 pamixer、cliphist、pavucontrol。状态：**已修改并验证，未切换系统**。

- 从 `aspects/default.nix` 移除 pamixer、pavucontrol；删除 Mango 中匹配 pavucontrol 的浮窗分支，保留 GTK Portal 规则。
- 删除 `modules/home/services/cliphist.nix`，移除文字和图片两个 watcher 及其包引用；Noctalia 原生历史和 Super+V 入口继续保留。
- 保留 `aspects/interactive-session/clipboard.nix` 的 X11/Wayland 桥、截图/OCR 及 wl-clipboard/xclip，不读取、清理或迁移历史数据库。
- 锁定 Noctalia 5.2.1 的源码覆盖总音量/麦克风、静音、默认设备、应用音量及输出路由；其 EasyEffects profile 不是声卡硬件 profile。后者及硬件端口高级操作使用已有 wpctl/pw-cli，README 已记录查询和选择方式，不新造图形混音器。
- 音量键和麦克风静音键继续直接调用 Noctalia IPC，没有改成新脚本。

验证结果：

- `nix flake check --no-build --no-write-lock-file` 通过。
- treefmt 检查和主机 `system.build.toplevel` 构建通过（`nix build --no-link --no-write-lock-file .#checks.x86_64-linux.treefmt .#nixosConfigurations.nixos-btw.config.system.build.toplevel`）。
- Home Manager 求值断言通过：三个工具无直接包声明、无 cliphist watcher，clipboard-bridge 保留；音量/麦克风键和历史入口保留。
- 已构建的 Home profile `/nix/store/iwqrw26f7ha17phwfl7h5nhsa4fgn41q-home-manager-path` 中三个命令不存在，Noctalia、clipboard-bridge、wl-copy、wl-paste、xclip 仍在。
- 当前运行的 Noctalia 为 5.2.1，确认与新 Home profile 使用同一个二进制。音频页与剪贴板页 IPC 打开检查通过，检查后恢复原来的关闭状态；未读取或更改剪贴板内容。
- WirePlumber 可读取当前默认输出和输入；Secret Service 默认 keyring 的锁定状态查询确认已解锁，未读取密钥或历史内容。
- 独立只读复核通过；文档本地链接和差异空白检查通过。剪贴板桥原有的工作树改动保留，不归入本次删项。

限制：没有切换系统，当前已应用世代的包和 watcher 尚未被本次构建替换；后续系统重建应用时才移除。没有实际播放/录音、切换声卡 profile、设备热插拔、逐项点击应用路由，或注销重登验证历史恢复；不把面板打开/密钥环解锁等同于这些完整场景已通过。没有性能测量，也未删除用户数据。

## 已确认的方向

| 主题 | 决定与状态 |
|---|---|
| 重构范围 | 全仓全面重构，允许破坏性整理；按阶段完成并留回退点。已决定。 |
| 框架 | 采用 Den（此前方案 C）；主机、用户和 aspect 使用 Den 的概念，role 是本仓库的组合约定。当前尚未加入 Den 输入，接线迁移未实施。 |
| 主机 | 保留 `nixos-btw` 的磁盘 UUID、Intel/NVIDIA 图形和设备专属配置在 host 层；未来服务器使用独立 host，不把笔记本硬件配置复制过去，也不虚构未确认的服务器部署参数。 |
| 桌面 | 保留 Mango + Noctalia。 |
| 终端 | 保留 Kitty + tmux。 |
| 配色 | 固定 OneDarkDarker，底色 `#1f2329`，以 `navarasu/onedark.nvim` 的 darker 风格为参考。 |
| Neovim | 已迁到原生 Lua + Nix 包入口；插件/parser 由锁定 stable 包固定提供。专项检查、完整主机构建及本轮记录的运行验证通过，未切换系统。 |
| JetBrains | 仅保留 IDEA、PyCharm、CLion；用户确认删除 WebStorm、DataGrip、RustRover，安装声明已移除。 |
| 工具链 | 采用混合工具链：系统常用工具由配置管理，项目级环境继续由项目自己的 flake 管理。用户项目 flake 不重写、不统一迁移。 |
| LaTeX | 用户会编译完整文档，完整 TeX Live 继续保留；编辑器自动公式预览已在前置清理阶段移除。 |
| 容器、虚拟机与工程工具 | 当前笔记本保留 Docker、libvirt/QEMU/KVM/virt-manager 整套、MATLAB 集成、STM32/Cortex-M 工具组及现有系统权限和入口；本轮不改成仅远程管理或项目按需环境。未来主机仍分别选择。 |
| 软件取舍 | 已确认项目按下表保留或删除；开发环境精简方案已实施并验证，Kdenlive 继续暂留待考虑。 |
| 笔记与阅读 | Obsidian、Typora、Zathura、Quill 用户已确认全部保留。 |
| 创作、办公与音乐 | Blender、GIMP、OBS Studio、Thunderbird、LibreOffice、Zotero、Musicfox 用户已确认全部保留；Kdenlive 仍暂留待考虑。 |
| 日用软件 | Firefox、QQ、微信、Discord、Clash Verge、Thunar、Yazi、mpv、截图/OCR、剪贴板历史、Fastfetch、btop 用户已确认全部保留。 |
| 游戏 | Steam、Prism Launcher、MangoHud、Gamescope、GameMode 用户已确认全部保留，维持现有 Minecraft 多 JDK 和辅助工具集成。 |
| Noctalia 插件 | 当前 10 项全部保留：Quill、mini-docker，以及 Bongocat、JetBrains/tmux/Prism Provider、IP Monitor、Portctl、Mango Layouts、Mango Keymode。 |
| 数据与应用 | 配置重构和系统切换是独立步骤。用户数据、模型权重、应用状态不得随包清理删除。 |

## 本批清理状态

以下项目在当前工作树已有删除或调整，状态为**已修改并验证，未应用**。检查结果列在本节末尾；用户数据未迁移或删除。

| 项目 | 本批目标 | 注意事项 |
|---|---|---|
| Pi CLI 与 Pi local | 删除 | 保留用户数据和模型权重。 |
| CopilotCLI、ccusage、crit | 删除 | 同步移除引用、快捷键和相关包。 |
| MCPorter | 删除 | 它与 MCPHub 是不同项目；MCPHub 也已在后续编辑器删减中单独确认移除。 |
| sandbox-runtime、workmux、Herdr | 删除 | 搜索脚本、服务、PATH 和文档残留。 |
| 本地 llama.cpp、模型下载服务与 helper | 删除配置和实现 | 保留已有模型权重及用户数据；当前运行服务由之后的系统应用步骤处理。 |
| 本地模型专用包与 Octave | 删除 `pkgs/llama-cpp.nix`、模型清单及 Octave 模块 | Octave 专用 `qt5ct` 一并移除；确认没有其他消费者。 |
| CodeCompanion 本地适配器 | 删除 | 删除本地 adapter 和 `<leader>al`；默认聊天改用现有 DeepSeek。Inline 和 cmd 原本已用 DeepSeek。 |
| CodeCompanion agent 清单 | 删除 Pi、CopilotCLI 条目 | 保留 Codex、Grok、OpenCode2。保留 `opencode` 兼容 wrapper，因为调用方使用该命令名。 |
| 桌面/服务集成 | 保留 DSH 桌面、GrokBot | MCPHub 在后续编辑器删减中单独确认移除。 |
| 工具兼容用途 | 保留 OpenCode、多个 JDK、TeX | OpenCode 当前供 QuillAI 使用；多个 JDK 供 Prism 使用；TeX 保留完整文档编译用途。重构前复核消费者。 |

### 本批验证记录（2026-10-18）

- 已通过：`nix flake check --no-build --no-write-lock-file`。
- 已通过：`nix build --no-link --no-write-lock-file .#checks.x86_64-linux.treefmt`。
- 已通过：`nix build --no-link --no-write-lock-file .#nixosConfigurations.nixos-btw.config.system.build.toplevel`。
- 已通过：独立 Nixvim 输出构建；隔离 XDG 配置、数据、状态、缓存目录后正常 headless 冷启动并触发 CodeCompanion 懒加载。
- 运行检查确认：chat/inline/cmd 为 DeepSeek，CLI 默认 Codex 且清单仅有 Codex/Grok/OpenCode，本地适配器和 `<leader>al` 已移除，MCPHub 和聊天历史集成仍存在，DeepSeek adapter 可解析。
- 求值断言通过：请求删除的软件不在 Home Manager 安装清单中，本地推理/下载服务不在生成的用户服务清单中；保留的 AI 软件仍在。
- 已通过：目标文件格式化、差异空白检查和一次独立只读集成复核。
- 未执行：真实 DeepSeek 网络请求、系统切换、GUI 交互回归、用户数据清理。当前运行中的软件/服务需在后续应用配置后才会更新。
- 本轮新增的是执行文档，不是新 Nix 模块；上述 Git flake 检查覆盖已有跟踪模块的本批配置改动，新文档另做本地链接和结构检查。

### 后续删项（2026-10-18）

用户确认删除 ProtonUp-Qt，以及 Noctalia 的 ShareDND、Kaomoji、DeepSeek Peak。已移除安装声明和插件启用条目；三个插件没有其他声明的 widget、capsule 或专用依赖需要清理。Noctalia 启用清单由 13 项减至 10 项。

Kdenlive 用户仍在考虑，暂时保留。此次不清理应用数据，也未切换系统；Noctalia GUI 保存的启用覆盖需在之后应用配置时检查。

验证状态：**已修改并验证，未应用**。本次 `nix flake check --no-build --no-write-lock-file`、treefmt 检查构建、主机 toplevel 构建均通过，目标文件格式和差异空白检查通过。Home Manager 求值断言确认四项声明已移除、启用插件为 10 项，Kdenlive、Blender、GIMP 与 Bongocat 仍保留。未进行桌面运行验证或系统切换。

### PDF、工程软件与看图（2026-10-18）

用户确认删除 PDF Arranger、KiCad：已删除专用 PDF Arranger 模块和 KiCad 包声明。PDF 阅读继续使用已确认保留的 Zathura；嵌入式工具不因 KiCad 删除而移除。yt-dlp 最初只解释用途，后续因用户认为作用不大，从常驻安装清单移除，见下文记录。

看图沿用 stable 锁定的 Swayimg 4.7，补齐具体图片 MIME 默认关联和可在启动器发现的 `swayimg.desktop`；不再依赖未声明的桌面默认选择。查看器使用深色底、适配窗口、自然文件排序和同目录翻图，缩略图保持完整比例。支持的格式以锁定包的解码库和源码为依据，涵盖 PNG/JPEG/GIF/WebP/SVG/HEIC/AVIF 等；不是依据当前上游主分支推定。4.7 使用 INI 配置，新版上游的 Lua 配置不适用。

操作：左右方向键或 `h/l` 翻图，滚轮缩放，左键拖动，`Enter` 或右键进入缩略图；缩略图中方向键选择、`Enter`/左键打开，`f` 全屏、`F1` 查看帮助、`q`/`Esc` 退出。旋转和翻转使用上游默认快捷键，只改变显示，不承诺写回图片。

IDEA/PyCharm/CLion 已确认保留。用途比较后，用户确认删除其余三个的安装声明：[WebStorm](https://www.jetbrains.com/webstorm/) 面向 JS/TS、前端框架和 Node.js；[DataGrip FAQ](https://www.jetbrains.com/help/datagrip/faq-about-datagrip.html) 说明其数据库功能与其他 IDE 的 Database Tools and SQL 插件相同，但完整功能取决于实际 IDE 授权；[CLion Rust 文档](https://www.jetbrains.com/help/clion/rust-plugin.html) 说明 Rust 插件与 RustRover 保持功能一致。此轮未读取授权或最近项目数据，也未自动安装额外 IDE 插件。

验证状态：**已修改并验证，未应用**。本次 flake 求值、treefmt 构建、主机 toplevel 构建、差异空白和本地文档链接检查均通过。Home Manager 断言确认 PDF Arranger/KiCad 已移除、Swayimg 和三个常用 IDE 仍在。隔离 XDG 配置并在当前 Mango 会话启动测试窗口，实际加载 PNG、JPEG、动图 GIF、WebP、SVG、HEIC、AVIF，逐个通过标题确认同目录翻图；缩略图模式启动正常，日志无解析或运行警告。构建产物的桌面条目可见，隔离 XDG 默认 MIME 查询七种格式均返回 `swayimg.desktop`。未切换系统，也未验证切换后现有用户配置覆盖下的 Thunar 双击行为；没有更改用户图片或应用数据。

### JetBrains 精简（2026-10-18）

已按用户选择移除 WebStorm、DataGrip、RustRover，仅保留 IDEA、PyCharm、CLion。现有 Skiko 库路径修复、Mango 浮窗提示修复和 Noctalia `/jb` 入口继续供保留的 IDE 使用。用户项目、授权、缓存和最近项目数据未删除；历史项目记录仍可能包含已移除的 IDE，之后应用时按实际入口处理。

验证状态：**已修改并验证，未应用**。目标模块格式化、flake 求值、treefmt 构建、主机 toplevel 构建均通过；Home Manager 断言确认三个保留 IDE 均在、WebStorm/DataGrip/RustRover 均不在安装清单中，`/jb` Provider 仍启用。代码配置中没有三个移除 IDE 的残留声明；文档本地链接和差异空白检查通过。未切换系统，也未重新执行 IDE 图形交互回归。

### yt-dlp 精简（2026-10-18）

用户认为视频下载用途有限，本轮移除 yt-dlp 独立安装声明，需要时再按需运行。仓库自定义配置没有直接命令调用；锁定 nixpkgs 的 mpv 包默认 `youtubeSupport = true`，其 `fallbackBinPath` 仍携带 yt-dlp，用于解析在线视频地址。因此不从依赖闭包强制移除，不影响 mpv 现有网络播放能力，也不承诺明显节省磁盘。浏览器和已有下载文件保持原状。ffmpeg 仍供其他音视频工作使用，继续保留。

验证状态：**已修改并验证，未应用**。flake 求值、treefmt 构建和 Home Manager 包环境构建通过；求值断言确认 yt-dlp 不在独立安装清单中、ffmpeg 仍在。目标模块格式化、差异空白和文档本地链接检查通过。未重新构建主机 toplevel 或测试真实网络视频，未切换系统。

## 软件盘点与待选择项

盘点以当前 `modules/`、`aspects/editing/neovim/config/`、`pkgs/` 中的声明为起点。决定删除某项前，先确认它是否有用户数据、项目或桌面入口消费者；清理配置不等于清理用户目录。

| 类别 | 当前清单 | 状态 |
|---|---|---|
| IDE | IntelliJ IDEA、PyCharm、CLion，以及 VS Code | 均已明确保留；WebStorm、DataGrip、RustRover 已移除安装声明。 |
| AI 与代理 | Codex、Grok Build、OpenCode2/兼容 `opencode`、DeepSeek Harness 桌面、Grok Bot；Neovim 的 CodeCompanion | 五个独立 AI 软件已决定先保留，后续明确不用时再删除；编辑器 AI 插件保持当前状态。 |
| 开发与语言 | Git、LLVM/Clang、Python、Lua、Java/JDK、MATLAB、嵌入式工具、Nix 工具、direnv、各类 LSP/格式化器 | 按已批准的下文方案精简；MATLAB、STM32、JDK、完整 TeX、Git/查包与编辑器工具继续保留。 |
| 笔记、文献与办公 | Obsidian、Zotero、LibreOffice、Typora、Zathura | 均已明确保留；PDF Arranger 已移除安装声明。 |
| 图像、视频与制作 | Blender、GIMP、Kdenlive、OBS Studio、mpv、Musicfox、ImageMagick、ffmpeg | Blender、GIMP、OBS Studio、Musicfox、mpv 明确保留；Kdenlive 用户仍在考虑，暂留；ImageMagick/ffmpeg 按消费者处理；yt-dlp 独立安装声明已移除。 |
| 浏览与通信 | Firefox、Thunderbird、Discord、QQ、微信 | 均已明确保留，保留现有账户集成与配置。 |
| 桌面与文件 | Mango、Noctalia、Thunar、Yazi、截图/OCR、剪贴板、输入法、音频与显示器工具 | Mango、Noctalia、Thunar、Yazi、截图/OCR、剪贴板历史明确保留；Clash Verge、Fastfetch、btop 同样保留；输入法、音频和显示器工具按工作流及依赖处理。 |
| 游戏与虚拟化 | Steam/Gamescope/GameMode、Prism Launcher、MangoHud、Docker、libvirt/QEMU、virt-manager | 均已明确保留；Prism 所需多 JDK 先保留。ProtonUp-Qt 安装声明已删除。 |
| 设备与专用工具 | STM32CubeProgrammer、tesseract、自定义差异查看工具等 | STM32 工具及调试探针权限保留；其余待选择。KiCad 安装声明已移除。 |

### 剩余选择菜单

Obsidian、Typora、Zathura、Quill 已全部确认保留，不再重复询问。JetBrains 仅保留 IDEA、PyCharm、CLion；Docker、本地虚拟机整套、MATLAB、STM32/Cortex-M 工具组也已明确保留。Blender、GIMP、OBS Studio、Thunderbird、LibreOffice、Zotero、Musicfox 同样已确认全部保留。日用批次（Firefox、QQ、微信、Discord、Clash Verge、Thunar、Yazi、mpv、截图/OCR、剪贴板历史、Fastfetch、btop）全部保留；Kdenlive 仍是暂留待考虑；五个独立 AI 软件按之前决定先保留。

| 功能组 | 尚未确定的软件或入口 |
|---|---|
| 视频剪辑 | Kdenlive 暂留待考虑。 |

开发工具声明集中在 [dev 模块目录](../aspects/)，日用包见 [packages.nix](../aspects/default.nix) 和 [apps 模块目录](../aspects/)，容器与虚拟机分别见 [docker.nix](../aspects/local-containers/host.nix)、[libvirt.nix](../aspects/local-virtual-machines/host.nix)。本次是声明和引用盘点，未据此推断实际使用频率。

JDK 同时供 Prism 使用；TeX 用于完整文档编译，Ghostscript 保留供普通 PDF/文档转换，编辑器自动公式图像流程已移除；ImageMagick 还供 Thunar 图片动作使用；编辑器工具按消费者保留。

### 开发环境优化方案（2026-10-18）

用户已批准开发环境优化方案，并补充会编译完整 LaTeX 文档、一般不在 Neovim 预览公式。本节记录的全局工具精简批次当时未改编辑器；后续前置清理已移除自动公式流程，见本文开头。用户自己的项目 flake 不改写，也不为其自动添加依赖。

| 类别 | 已批准的范围与实施状态 | 改变及约束 |
|---|---|---|
| C/C++ | 全局保留 Clang/LLD、CMake、Ninja、pkg-config、GDB；移除 Meson、ccache 独立安装声明，改由项目或按需提供。 | 普通 shell 不再直接提供 Meson、ccache；ccache 只有项目显式启用才生效。Clangd/clang-format 仍供编辑器使用，ARM 工具组按先前决定保留。 |
| Python | 全局提供共享原生 Python 3 和 uv；移除全局 IPython 环境。 | 普通 `python3` 和 uv 工作流保留；IPython 通过下文锁定输入的按需命令运行。仓库 Python 脚本使用自己的固定 store 解释器。 |
| Lua | 全局保留 Lua 5.4；移除独立 LuaJIT、LuaRocks 安装声明。 | Neovim 使用自身运行时，不依赖独立 `luajit` 命令；移除 `use-luarocks` 和 `~/.luarocks/bin` 的全局 PATH 接线，已有用户 rocks 文件不删除。Lua 语言服务器、luacheck、stylua 保留。 |
| Java | 保留当前 JDK 8/17/21/25/26 和默认 25。 | 版本集合已经由 shell、Gradle 和 Prism 共用；没有已核实的实例/项目版本需求清单，不能将某版本判为多余。IDE 自带 JBR 与用户项目 JDK 用途不同。 |
| LaTeX | 保留完整 TeX Live；不按预览最低宏包集合替换。 | 会编译完整文档，未核对论文模板前不缩减宏包。编辑器自动公式 helper/事件/渲染配置已在后续前置阶段移除；Ghostscript 仍供普通 PDF/文档转换，ImageMagick 另供 Thunar 使用。 |
| Git 与查包 | 保留 GH CLI、lazygit、delta、nix-index/comma。 | 分别承担 GitHub 操作、Git 交互、差异显示和命令查包/临时运行，保留现有接线。 |
| 默认 devShell | 保留仓库维护入口；其职责在 Den 迁移时收束为本仓库维护。 | 和全局使用同一 store 路径不等于安装两份，不以重复写出包名为由声称省空间。项目的编译器和依赖继续由各自 flake 固定。 |
| CUDA devShell | 已移除额外 `cuda_nvcc` 声明，保留 `cudatoolkit`、cuDNN、`CUDA_PATH`。 | 锁定源码的 `cudatoolkit` 已包含相同版本的 nvcc；求值确认 nvcc 输出在其 paths 中。此次只清理重复声明，不改工具能力、不声称减少依赖闭包。 |

当前已实现闭包的独立测量：完整 TeX Live 5943.1 MiB，Python 3 为 200.2 MiB，含 IPython 的 Python 环境 245.0 MiB，Lua 5.4 为 41.6 MiB，独立 LuaJIT 为 48.2 MiB，LuaRocks 为 150.8 MiB。方法为 `nix path-info --json --closure-size`，以当前锁定包输出为对象。各闭包存在共享，数字不能相加或直接当作系统可释放空间；旧系统代仍可能保留引用。当前 CUDA 环境未实现，未为盘点下载完整 CUDA 工具链。

按需工具在本仓库目录通过锁定输入取得；项目仍继续使用自己的 flake。以下命令只对临时环境提供工具，不重新加入全局安装；尚未缓存的包仍需下载。`--inputs-from` 的语义已对照本机 `nix shell --help`，不引入在线 Python 包安装器作为本次替代方案。

```sh
# 临时运行 IPython
nix shell --no-write-lock-file --inputs-from . nixpkgs#python3Packages.ipython --command ipython
# 为当前终端提供构建辅助工具
nix shell --no-write-lock-file --inputs-from . nixpkgs#meson nixpkgs#ccache
# 选择 Lua 项目需要的运行时/包工具
nix shell --no-write-lock-file --inputs-from . nixpkgs#luajit
nix shell --no-write-lock-file --inputs-from . nixpkgs#lua5_4 nixpkgs#lua54Packages.luarocks
```

验证状态：**已修改并验证，未应用**。目标模块格式化、flake 求值、最终 treefmt 构建、主机 toplevel 构建通过。求值断言确认五项独立声明移除，常用工具与编辑器工具保留，LuaRocks PATH/helper 消失；生成的 Zsh 配置语法和五个 JDK 版本检查通过。新 Home Manager 包环境检查确认 `meson`、`ccache`、`ipython`、`luajit`、`luarocks` 不在其 bin 目录中；原生 Python 在隔离模式下启动且无 IPython 模块，Lua 5.4 启动通过。以新包环境 PATH 和隔离 XDG 目录冷启动 Neovim，内嵌 LuaJIT、clangd、Lua LS 入口检查通过。五项工具的锁定输入按需版本命令也全部运行通过。一次独立只读复核未发现遗漏引用；文档链接和差异空白检查通过。CUDA 清理仅验证求值和 nvcc 依赖包含关系，未构建整套 CUDA 或执行 GPU 编译。未切换系统、清理用户数据或重写用户项目 flake。

### 已确认保留的四组及后续边界

用户已确认 Docker、本地虚拟机整套、MATLAB、STM32/Cortex-M 工具组全部保留，继续采用当前安装和服务配置。下表保留功能说明及后续可讨论的拆分边界；本轮不实施这些拆分，也不自动把工具移入项目 flake。

| 组 | 当前配置 | 选择边界 |
|---|---|---|
| Docker | [rootless Docker 与每周 prune](../aspects/local-containers/host.nix)，以及 Noctalia mini-docker 入口。 | 本机运行容器时保留引擎；仅管理远程服务器可另设计 CLI/远程连接，笔记本不必同时运行本地引擎。项目 devShell 提供编译环境，不直接提供系统 Docker 服务。 |
| 虚拟机 | [libvirt/QEMU/KVM、virt-manager、TPM、USB 重定向](../aspects/local-virtual-machines/host.nix)，并启用嵌套 KVM；`libvirt-guests` 被关闭，未检查现有 VM 自启动状态。 | 本机运行完整客体系统时保留；以后只管理远端虚拟机时，可将客户端与本地虚拟化服务分开。未来服务器需要虚拟化，不要求当前笔记本也启用。 |
| MATLAB | [FHS 启动集成](../aspects/languages/matlab/home.nix) 和编辑器语言支持；MATLAB 本体由用户手工安装。 | 课程/项目依赖 MATLAB、Simulink 或工具箱时保留；移除 Nix 集成不等于卸载手工安装树，也不自动删除 `.m` 文件。未检查授权和安装状态。 |
| STM32/Cortex-M | [ARM GCC、OpenOCD/ST-Link/probe-rs、DFU/UART、CubeMX、CubeProgrammer、tio](../aspects/embedded-workbench/home.nix)，另有 [USB 探针权限](../aspects/embedded-workbench/host.nix)。 | 编写、烧录、调试开发板固件时使用，独立于已经删除的 KiCad。可保留设备权限和常用 GUI，将版本敏感的编译/调试命令放进项目 flake；普通 devShell 不能代替系统 udev 权限配置。 |

功能依据：[Docker 概览](https://docs.docker.com/get-started/docker-overview/) 与 [rootless 模式](https://docs.docker.com/engine/security/rootless/)、[virt-manager](https://virt-manager.org/)、[MATLAB](https://www.mathworks.com/products/matlab.html)、[STM32CubeMX](https://www.st.com/en/development-tools/stm32cubemx.html)。本轮只核对配置和资料，未更改四组模块或运行服务。

### Noctalia 已确认插件

Mango + Noctalia 已选定，以下是删除 ShareDND、Kaomoji、DeepSeek Peak 后的 10 项启用声明。用户已确认全部保留；保留现有栏组件、启动器入口和专用依赖，本轮没有改变插件配置。

| 用途 | 当前启用 |
|---|---|
| 桌面操作 | Mango layouts、Mango keymode |
| 应用/会话入口 | JetBrains provider、tmux provider、PrismLauncher instances |
| 系统管理 | IP monitor、mini-docker（随 Docker 保留）、portctl |
| 笔记待办 | Quill（已明确保留；AI 功能当前调用 OpenCode） |
| 装饰/附加 | Bongocat |

### 删除决策优先，替换和新增随后

用户已明确要求先确定删哪些，再对保留的软件评估替换和补充。本阶段不以替换产品的承诺作为删项理由，不进行输入升级或软件新增。

| 项目 | 当前决定 | 下一步 |
|---|---|---|
| VS Code | 用户明确保留 | 保留 FHS 包与扩展兼容配置。 |
| Obsidian / Typora / Zathura / Quill | 用户明确全部保留 | 从删除候选中移出，保留笔记、阅读、待办及其现有集成。 |
| IDEA / PyCharm / CLion | 用户明确保留 | 保留现有通用启动修复及项目入口。 |
| Docker / 本地虚拟机 / MATLAB / STM32 工具组 | 用户明确全部保留 | 维持现有安装、服务、设备权限及入口；本轮未更改相应模块，仅更新决策记录。 |
| Steam / Prism Launcher / MangoHud / Gamescope / GameMode | 用户明确全部保留 | 保留当前游戏配置、Prism 辅助工具与多 JDK 集成；本轮仅更新文档，未改模块。 |
| WebStorm / DataGrip / RustRover | 用户确认删除，安装声明已移除 | 保留用户项目与状态，不自动安装额外 IDE 插件。 |
| Codex / Grok Build / OpenCode / DeepSeek Harness / Grok Bot | 用户决定先保留 | 从本轮删除候选移出；相关 Neovim、Quill、桌面和 URL 入口保持。 |
| ProtonUp-Qt | 用户确认删除，已移除安装声明 | 不再提供该图形化额外 Proton 版本管理工具。 |
| PDF Arranger / KiCad | 用户确认删除，已移除安装声明 | 保留 Zathura 阅读 PDF；保留独立的嵌入式开发工具。 |
| yt-dlp | 用户认为用途有限，本轮移除独立安装声明 | mpv 仍携带其网络播放依赖；已有下载文件保留，需要独立下载时按需运行。 |
| ShareDND / Kaomoji / DeepSeek Peak | 用户确认删除，已移除启用声明 | 不再提供对应拖放、颜文字搜索和高峰倒计时插件；待应用时检查运行时覆盖。 |
| Bongocat | 用户明确保留 | 保留键盘/音频动画及其 `evtest` 依赖。 |
| JetBrains / tmux / Prism 启动器 Provider | 用户明确全部保留 | 保留 `/jb`、`/tm`、`/pl` 入口及 tmux Provider 所需 `tmuxp`。 |
| IP Monitor / Portctl / Mango Layouts / Mango Keymode | 用户明确全部保留 | 保留现有栏组件、布局切换和按键模式显示。 |
| Kdenlive | 用户仍在考虑，暂留 | 剪辑需求尚未确定，后续再选择。 |
| Blender / GIMP / OBS Studio / Thunderbird / LibreOffice / Zotero / Musicfox | 用户明确全部保留 | 保留现有包与集成，不再列入删除候选；本轮仅更新文档，未改模块。 |
| Firefox / QQ / 微信 / Discord / Clash Verge / Thunar / Yazi / mpv / 截图与 OCR / 剪贴板历史 / Fastfetch / btop | 用户明确全部保留 | 保留现有日用集成，不再列入删除候选；本轮仅更新文档，未改模块。 |
| 全局开发工具 | 用户批准精简方案，按上文实施 | 保留常用工具、JDK、完整 TeX、Git 与查包；Meson/ccache/IPython/独立 LuaJIT/LuaRocks 按需提供。 |

候选依据与耦合边界：

- ShareDND 的锁定实现要求 `NIRI_SOCKET` 和 `niri` 命令；在其他合成器下不启动检测。删除是去掉不适用配置，不等于修复一个正在消耗资源的后台服务。
- 已移除的 Kaomoji 提供 `/kao` 搜索复制，DeepSeek Peak 提供时段面板/组件。Bongocat 仍保留；删除后会失去键盘/音频动画。配置中的 `evtest` 专供 Bongocat 使用，之后若删除仍需确认没有新增消费者。
- JetBrains Provider 只是最近项目启动入口。tmux Provider 还使用 `tmuxp`；移除该 Provider 时，先判断用户是否独立使用 `tmuxp`。Prism Provider 不负责安装游戏或提供 JDK。
- Musicfox 是独立音乐客户端，Noctalia 媒体控件并不完整提供其功能。PDF Arranger 是已确认删除的页面整理工具，Zathura 继续承担阅读用途。
- mini-docker、portctl、IP monitor 在当前栏中都有明确入口；Quill 提供笔记、待办与可选 AI。这些插件已经全部确认保留，之后重构保持现有入口。
- JDK、TeX、ImageMagick、ffmpeg、Node.js、LSP、显卡/设备权限仍可能被其他程序使用；删除上层应用后，再通过消费者和构建结果判断哪些依赖确实不再需要。

每个删项按同一顺序执行：

1. 记录用户选择和删后功能变化；未明确的项目保持现状。
2. 去掉包或专用模块，再清理快捷键、桌面入口、MIME、插件 Provider 和文档。不要仅卸掉可执行文件却保留调用者。
3. 删除 Noctalia 插件时同步处理 `enabled`、capsule 成员、widget 配置和专用依赖。应用时还需检查 GUI 保存的插件启用覆盖，不能只凭 Nix 数组推断运行状态。
4. 不删除软件库、模型、账号、笔记或其他用户数据；不把停止服务与移除安装声明混成一步。
5. 按影响执行求值、相关构建和最小必要运行检查；在本文更新为“已修改并验证，未应用”。
6. 软件保留范围稳定后，单独制定替换/补充方案，再继续结构、主题和 Lua 迁移。

## 实体、选择与完整功能的新架构

最新方案见 [架构设计](architecture-design.md)。本节替代前版按现有软件分类或官方模板目录扩展的目标树；当前配置稍后逐一适配，不以原路径和文件名限制架构。

- 实体与绑定描述事实、账号和明确选择；用途组合是普通 includes；完整功能拥有系统/HM/账号配置与依赖。
- 一次选择配齐功能内部两侧，并用所锁 Den 的原生机制定向投递。取消公开调用界面上 workstation/desktop 等人工配对。
- 功能资源、包配方和专项测试就近放置；显式登记入口，使私有 `.nix` 不会被当成顶层模块扫描。
- 外观、默认工具和语言贡献等实际共享数据先定义所有权、类型、作用域、合并与写入者，再选择 schema/quirks/pipes。
- 不搭建第二套角色、provider 或依赖注入框架；先证明纵向样本，再逐项迁移当前配置。

## 后续功能与视觉设计

新架构先确定边界与协议；下面的编辑器树记录当前已实现状态，不是未来位置必须保持的约束。软件保留决定继续有效。

### Lua 编辑器分层（当前实现）

```text
aspects/editing/neovim/config/
├── init.lua
├── after/queries/           # 自定义 highlights 与 Nix injections
├── colors/                  # 手写 One Dark Darker
├── lua/mayon/
│   ├── core/                # options、keymaps、autocmds、icons
│   ├── features/            # 原生会话、URL 等
│   ├── lsp/                 # servers、诊断与 attach 行为
│   ├── plugins/             # 保留插件的直接 setup
│   └── ui/                  # 主题、Noice 与界面适配
└── snippets/               # 仓库自有片段
aspects/editing/neovim/                 # stable wrapper、插件、parser 清单
nix/neovim.nix             # neovim / neovim-dev outputs
```

- Nix 声明 Neovim、20 个直接插件、32 个显式 parser 及必要依赖；Lua 直接配置插件。使用锁定 stable 的 `wrapNeovimUnstable pkgs.neovim-unwrapped`；不使用 deprecated `makeNeovimConfig`。
- 用户最新确认移除 `lz.n`；保留插件显式直接加载，迁出原触发配置内的映射；不引入在线安装/升级或另一套自制加载器。
- 先建立现有功能到新文件的映射，再搬配置；此前已删除的 render-markdown、Harpoon、Todo Comments 等保持删除状态，原生替代功能继续保留。
- LSP/格式化工具按所选语言由 Nix 提供；项目特定编译器和依赖从项目环境获得。CLI 启动与图形启动的 PATH 都要验证。
- 普通入口为 `nix run .#neovim`，开发入口为 `NVIM_CONFIG_DIR="$PWD/aspects/editing/neovim/config" nix run .#neovim-dev`；只有 dev 包响应环境变量覆盖。仅将 Lua 写进 store 不会自动获得免构建热修改能力。
- 求值、构建、隔离启动、终端交互与真实语言服务核验已完成，详细记录见本文开头和 [Neovim 迁移计划](neovim-migration-plan.md)。Colorizer/Matchup 与 Heirline/Navic 已由原生实现替代，后续接线仍需保留功能。

### One Dark Darker 配色与文件归属

以 `navarasu/onedark.nvim` 的 darker 配色为基准。以下角色映射是设计值，实际可读性仍需界面检查。

| 角色 | 色值 |
|---|---|
| 主背景 | `#1f2329` |
| 更深背景 | `#181b20` |
| 卡片/次级背景 | `#282c34` |
| 正文 | `#a0a8b7` |
| 次级文字 | `#7a818e` |
| 主强调蓝 | `#4fa6ed` |
| 次强调紫 | `#bf68d9` |
| 成功绿 / 警告黄 / 错误红 | `#8ebd6b` / `#e2b86b` / `#e55561` |

- 在仓库维护一份明确的角色/ANSI 色表，生成 Noctalia 的自定义 palette、Mango 颜色及终端/编辑器适配。Noctalia 使用固定暗色，不随壁纸或时间切换。
- 每个输出文件只保留一个写入者。计划由 Nix 管理的应用配色文件，要先停用写相同目标的 Noctalia 模板；应用确需可写的设置与 Nix 配色文件分开。
- Kitty 保留当前字体与 tmux 工作流，固定主题后梳理现有可写主题 stub 是否仍有必要；不能未经验证直接改变文件归属。
- GTK/Qt 和保留的第三方应用分别适配。表格记录支持范围与限制，不承诺所有软件都能逐像素统一。
- 建议面板布局：左侧启动器和工作区，中间时间，右侧常用状态；已确认保留的容器、端口、笔记等入口集中到二级面板。具体位置在桌面美化阶段设计，保留已确认的插件功能。
- 动画、透明和模糊分开调节；先测频谱、Bongocat 和插件开关的实际影响，再选择配置，不按插件数量推断性能。
- ShareDND 在锁定插件源码中仅支持 niri；当前 Mango 会话无效，用户已确认删除，其启用声明已移除。

## 分阶段执行与验收

### 1. 完成本批清理

- 检查每项删除的 diff、引用、服务、快捷键、桌面入口、文档和持久化数据路径。
- 保留前表指定的 AI 工具和兼容 wrapper；验证 CodeCompanion 默认聊天实际走现有 DeepSeek。
- 验收：引用搜索无意外残留；Nix 求值/相关构建成功；针对编辑器和桌面入口做冷启动或运行验证。本轮实际检查结果见“本批验证记录”。
- 回退：用阶段差异快照定位并回退造成故障的改动，保留此前用户改动；模型权重和用户目录不通过配置回滚覆盖。

### 2. 确定其余软件的保留范围

本阶段软件选型已结束。新增 Xarchiver、Okular；Kdenlive 按暂留现状进入后续阶段。接下来先执行 Neovim 专项计划，再接 Den；其他条件新增项以后按真实需求单独决定。

- Docker、本地虚拟机整套、MATLAB、STM32/Cortex-M 工具组已全部确认保留；只决定当前笔记本，未来服务器按 host/role 单独启用。创作、办公、邮件、音乐、日用、游戏与 Noctalia 插件均已确认保留；开发环境精简方案也已获批准。Kdenlive 继续暂留待考虑，后续按保留现状进入结构设计。
- 与用户逐类确认上表待选项；每项记录用途、消费者、数据位置、保留或删除理由。
- 删除前搜索声明、快捷键、脚本、MIME/桌面入口、服务、项目环境和文档引用；对工作区数据只做盘点，不做自动迁移或删除。
- 验收：保留清单与软件声明一致；移除项没有活动消费者；所需应用数据路径有明确保留策略。
- 回退：按类别保留独立差异；恢复被删声明不应清理/覆盖用户数据。

### 3. Neovim 迁移到原生 Lua（已接入并验证，未应用）

- 配置已整理为 `aspects/editing/neovim/config/` 原生 Lua 模块；插件与 parser 由 Nix 固定提供，不使用在线自更新插件管理器。
- 独立入口为普通 `neovim` 和可覆盖配置路径的 `neovim-dev`；Home Manager XDG init 与包入口共用 Lua init，并以幂等标记避免双重执行。
- `checks.neovim` 已通过完整 startup、真实 Blink C++ snippet 加载/展开/跳转和 native、statusline、tabline、breadcrumbs、LSP 样本；flake check、treefmt、host toplevel、HM 输出与实际 PTY 交互也通过。真实 LuaLS/CSSLS 和 StyLua 另行集成验证通过，见专项记录。
- 已确认单一活动入口、旧 Nixvim input/module 移除及运行时选项/键位/解析器/服务配置保留；桌面菜单、Kitty 图像、MATLAB 和 AI 网络调用等未实测，求值/构建不等同于完整 UI 验收。
- 回退：使用包含当前工作树的阶段快照；新入口失败时恢复旧入口，不混用两套活动配置或用户缓存。

### 4. 接入 Den 主机与职责边界

新方案见 [架构设计](architecture-design.md)，已由主代理与 Astra 交叉设计。[Den 样本](../tests/README.md) 已固定 v0.19.0，通过 shell 与嵌入式两条路径的两主机/两账号选择、共享资源去重及 shell 单值冲突检查。嵌入式工具、规则、包配方已收拢到 [功能目录](../aspects/embedded-workbench/README.md)；旧入口兼容引用仅用于当时的迁移过渡，批次 7 完成后旧适配器与兼容入口已退出。最终规则检查发现并修正 ST-Link 0666 权限，改为 0660/uaccess 且保留别名。真实笔记本构建、样本 HM/udev 与 ARM 编译/GDB/CLI 检查通过，尚未切换或验证设备。

外观、默认工具和语言协议已各自进入功能目录并由同一样本消费。数据/启用/安装的边界、用户与主机隔离、命令整体合并及同 ID/跨 ID 冲突已验证；Kitty parser、Neovim 高亮、wrapper 参数与 MIME、C++ 编译和 clangd hover 的运行检查通过，相关负例也被拒绝。以上为接入前样本阶段的历史结果。真实主机现已迁入 Den，旧适配器与兼容入口已退出；当前检查见实施记录。

- 先选定并锁定 Den revision，只增加所需新锁项、不顺带升级现有输入；读取该 revision 的源码文档和导入/模块行为，记录真实 API 和接线图后实现。
- 建立实体/绑定、普通组合 aspect 和完整功能入口；先验证 shell 与嵌入式功能的系统/HM/账号路由，随后逐项适配软件和服务。
- 区分 UUID/设备地址等事实与内核、驱动、电源等策略和实现。扫描工件显式引用；不创建假服务器参数。
- 先重构旧 `importDir` 接线，再移动文件。不要将 helper、包或 Lua 文件移入自动导入目录。
- 验收：flake 求值和相关输出构建成功；导入集合无遗漏或重复；笔记本硬件配置仍从 host 入口进入；秘密不出现在 store。
- 回退：保存每批迁移前后的差异快照和旧入口；出现求值或配置行为缺失时恢复该批入口，不能同时保留双份导入。

### 5. 固定主题为 OneDarkDarker

- 主题实现、编辑器高亮、Noctalia/桌面颜色和终端颜色按实际主题能力分别迁移，统一基准色为 `#1f2329`。
- 检查普通窗口、浮窗、选择区、诊断、语法高亮、终端和浅色背景内容的对比度；不保留旧主题切换代码作为隐性运行路径。
- 验收：Neovim 冷启动后无旧主题引用；Mango + Noctalia、Kitty + tmux 的色彩一致性由运行截图或现场检查确认。
- 回退：保留主题阶段前配置 diff；主题缺色时先修补明确的色值映射，不触碰主机或用户数据。

### 6. 稳定职责边界、检查与文档

- 复核实体/绑定、组合、完整功能与公开数据接口，验证定向路由、冲突、权限隔离和单一写入者；为共享边界加最小必要检查。
- 更新仓库入口文档、模块索引和工作说明，使其描述新的目录、导入规则、工具链和真实验证结果。
- 验收：格式、flake 求值、treefmt 构建、主机 toplevel 构建按影响执行；Neovim/桌面行为有独立运行验证；文档链接和事实对应当前配置与锁定源码。
- 回退：文档跟随实际状态修正，不以旧说明强迫配置回到旧结构；结构变化按最近一个通过验收的阶段回退。

## 安全、验证与应用边界

- 按用户要求频繁提交：每个可审查的小阶段完成必要验证后由主代理提交。允许推翻设计与实现，按实际结果修正边界；提交只包含对应阶段范围。

- stable `nixos-26.05` 是默认 `pkgs`；`pkgs-unstable` 只用于既有明确例外或 stable 确实无法满足的包。修改前核对 `flake.nix` 与锁定输入。
- 不给 `mango`、`noctalia-greeter`、`mark-shot`、`wayscrollshot`、`llm-agents` 添加 `follows`；这些输入各有源码依赖组合或预构建缓存约束。
- 秘密仅通过 sops 运行时文件或模板提供，不进入 Nix 字符串、构建日志、提交内容或 store。检查新 flake 源范围时排除运行时秘密。
- 修改 workaround 前先读原因，再按当前锁定源码或实际运行验证；历史测量不作为当前结论。发现旧文档与当前模块/锁定源码矛盾时一并更正。
- 常用检查命令：

```sh
git status --short
nix fmt
nix flake check --no-build --no-write-lock-file
nix build --no-link --no-write-lock-file .#checks.x86_64-linux.treefmt
nix build --no-link --no-write-lock-file .#nixosConfigurations.nixos-btw.config.system.build.toplevel
```

- `nix flake check --no-build` 只验证求值，不证明构建成功；构建成功也不代表配置已应用。按改动范围选检查，报告实际运行的命令和结果，不预填“通过”。
- 新文件尚未纳入 Git 跟踪时，Git flake 可能看不到它。若要用 `path:.`，先审查将进入 Nix store 的完整源范围并确认没有秘密或不应复制的本地文件。需要归档新文件以供 Git flake 检查时，应在确认源范围后建立正确的跟踪快照；不得用 `git add` 伪装用户批准。
- 除非任务明确包含应用配置，默认不切换系统、不升级输入。应用是单独且明确的步骤：`sudo nixos-rebuild switch --flake .#nixos-btw`（`nr`）。Home Manager 随 NixOS 重建，没有独立 switch。
- 用户数据处理与系统切换分开计划、分开执行；构建不会迁移应用数据，也不会应用配置。未经用户明确要求，不删除模型权重、笔记、文献库、桌面应用状态或其他用户文件。
