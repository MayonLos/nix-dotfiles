# 操作方式设计

状态：2026-10-18，Den 操作设计及后续窗口体验已由用户 nr 应用，本轮进一步优化获授权继续应用。按键/argv/cwd、tmux 键表及编辑器的隔离检查见 [实施记录](history/den-execution.md)；实际 GUI、文件管理器和项目交互仍待验收。

## 操作层次

| 范围 | 入口 | 规则 |
|---|---|---|
| 桌面窗口与工作区 | `Super` | Mango 拥有，不占用编辑器常用的 Ctrl/Alt 字母 |
| 桌面启动器 | `Alt+Space` | 保留现有入口；键盘、面板点击调用同一 Noctalia 功能 |
| 终端复用 | `Ctrl+a` 前缀 | tmux 管 pane/window/session；取消当前无前缀的 Alt 字母/数字拦截 |
| 编辑器窗口与功能 | `Ctrl+h/j/k/l`、Space leader | 保留现有 Neovim 行为；不跨层猜测当前应用然后转发按键 |
| shell 与 TUI | 原应用按键 | `Alt+b/f`、`Ctrl+r`、Esc 等正常到达应用 |

迁移前 tmux 的无前缀 `M-h/j/k/l`、`M-n/p`、`M-Tab`、`M-1…9` 会在 pane 内应用收到之前截获按键；现已改为前缀操作。`Ctrl+a Ctrl+a` 仍发送字面 Ctrl+a 给 shell；复制、选区和窗口管理不自动互相接管。依据当前 [tmux 配置](../aspects/command-line/tmux.nix) 和 [tmux 官方入门](https://github.com/tmux/tmux/wiki/Getting-Started)。

## 桌面主要操作

下表是完整保留的主要入口；具体命令沿用已锁 Mango 行为，默认应用启动改为 default-tools 的 argv wrapper。此表描述已实现的声明；实际按键效果仍需应用后核验。

| 操作 | 按键 | 声明行为 |
|---|---|---|
| 终端 / 文件 / 浏览器 | `Super+Enter` / `Super+E` / `Super+B` | 调用统一默认工具，禁止各入口独立硬编码应用 |
| 临时终端 | `Super+Shift+Enter` | Kitty 命名 scratchpad，首次启动，再次显示/隐藏 |
| 临时文件 / 系统监视 | `Super+Alt+E` / `Super+Alt+M` | 分别呼出独立 Kitty class 的 Yazi / btop；普通 Kitty 不受匹配 |
| 特殊工具工作区 | `Super+Shift+S` | 显示/隐藏 Tag 0，默认 scroller |
| 停放 / 取回特殊窗口 | `Super+Ctrl+S` | 将当前窗口放入 Tag 0；在 Tag 0 使用时送回先前普通 tag，不主动跟随 |
| 跨工作区可见 / 置顶 | `Super+Ctrl+G` / `Super+Alt+G` | 两个独立手动状态；前者限窗口所在输出，后者可能覆盖全屏窗口 |
| 控制中心 / 剪贴板 | `Super+S` / `Super+V` | 保留 Noctalia 单一入口 |
| 勿扰 / 防空闲 | `Super+Alt+D` / `Super+Alt+I` | 原生 DND / caffeine；面板铃铛与咖啡状态可见 |
| 锁屏 / 会话菜单 | `Super+Alt+L` / `Ctrl+Alt+Delete` | 菜单含有文字的退出/重启/关机确认；锁屏可直接触发 |
| 窗口聚焦 | `Super+h/j/k/l` 或方向键 | 保留两组等价入口 |
| 移动窗口 | `Super+Shift+h/j/k/l` 或方向键 | 保留；不混作显示器移动 |
| 移到相邻显示器 | `Super+Ctrl+方向键` | 保留，不为当前锁定版本捏造 HJKL 方向语义 |
| 去工作区 | `Super+1…9` | 编号稳定，不随应用关闭重排 |
| 移窗口并跟随 | `Super+Shift+1…9` | 保留 Mango `tag` 的实际语义 |
| 停放窗口、不跟随 | `Super+Ctrl+1…9` | 保留 `tagsilent`，帮助中说清差异 |
| 最近窗口 / 概览 | `Super+Tab` / `Super+0` | 保留 |
| 调整大小 | `Super+R`，随后 HJKL/方向键 | 保留模式；模式内 Esc 退出，所有模式下 `Super+Esc` 可退出 |
| 最大化 / 真全屏 | `Super+F` / `Super+Shift+F` | 保留二者差异 |
| 浮动 / 布局 / 主窗口 | `Super+Space` / `Super+W` / `Super+Z` | 布局仍为 tile/scroller/monocle；不模拟不存在的 niri 操作 |
| 关闭窗口 / 重载配置 | `Super+Q` / `Super+Alt+R` | 所有 Mango 模式可达；不全局拦截裸 Esc |
| 最小化 / 找回 | `Super+Shift+grave` / `Super+grave` | 成对保留，帮助说明与命名临时终端不同 |
| 操作帮助 | `Super+F1` | 显示同一份按键数据生成的分组帮助；新增工具键同步出现在帮助中 |

工作区默认按用途设置布局：1 开发 tile（主区域 60%）；2 浏览/资料 scroller（默认宽度 80%）；
3 通讯 tile；4 文档 monocle；5 专业工具 tile（主区域 65%）；6 媒体 monocle；7 虚拟化 tile；
8 游戏 monocle；9 临时 tile。Tag 0 使用 scroller（65%），为临时工具提供独立层次。
这是布局默认值，不是 app-id 自动分配；任意应用仍能放在任意 tag，`Super+W` 仍可切换布局。
改变声明中的布局默认值并重载会应用新默认，不代表长期恢复每个工作现场。
显示器使用各自真实输出事实，没有硬编码外屏分配或 niri 式自动恢复承诺。

named scratchpad 只有一个可见，呼出另一工具会隐藏前一个；跨屏呼出会使用当前输出。
这些操作只控制窗口显示，不终止其中的 shell、文件操作、监视器或后台任务。
普通最小化池、named scratchpad 与 Tag 0 是三个入口，不互相代替。

Firefox 的英文标题 `Picture-in-Picture` 精确匹配浮动、跨 tag、安静打开，默认 480×270，
靠右下方放置；不默认 overlay，避免主动压住全屏内容。需要置顶时手动 `Super+Alt+G`。
其他语言的标题、首次创建时机和实际浏览器行为留待验收，不使用所有 Firefox 窗口都命中的规则。
Noctalia 设置、portal 文件选择及 Swayimg 使用相对输出尺寸；Thunar 重命名保留应用尺寸提示。
父窗口关联、模态与 IDE 弹窗沿用 Mango/应用逻辑；未用宽泛规则让整个 IDE 浮动或禁止聚焦。
精确到父窗口中心、跨屏 DPI 无缝恢复和所有应用的焦点策略不是当前实现承诺。

现有进阶操作（master 数量/比例、scroller 比例、隐藏边距、特定显示器开关等）继续保留，归入帮助的进阶分组；只对重复或冲突的入口去重，禁止因未列入主表就静默删除。完整来源是 [Mango 配置](../aspects/interactive-session/mango.nix)。

## 截图、文件和剪贴板

| 操作 | 入口 | 保留的行为 |
|---|---|---|
| 区域/窗口截图与标注 | `Print` | mark-shot，保留 Mango 窗口检测适配 |
| 当前屏幕到剪贴板 | `Ctrl+Print` | 按指针所在输出选择，不能固定 eDP-1 |
| 滚动截图 | `Shift+Print` | wayscrollshot |
| 区域 / 全桌面 OCR | `Super+Print` / `Super+Shift+Print` | 英文+简体中文；取消选区安静退出，失败有提示 |
| 截图文件位置 | 应用保存动作 | 显示真实目标路径；用户已选路径不被激活脚本重置 |
| 打开 / 看图 | MIME 默认 | Thunar；图片 Swayimg；PDF Zathura 默认、Okular 可选；文本图形默认 VS Code，CLI 默认 Neovim |

保留 Thunar 的“在此打开终端”“复制为图片”“复制路径”“粘贴剪贴板图片”“粘贴为链接”。文件 URI、路径文字、图片像素是三种不同用途，不能为了减少代码把它们合并成一种复制。迁移终端入口时保持当前文件夹作为 cwd，路径包含空格/中文/引号仍正常，不经拼接 shell 字符串。当前实现见 [文件动作](../aspects/file-manager/thunar-actions.nix)、[终端入口](../aspects/file-manager/thunar-terminal.nix)、[截图](../aspects/interactive-session/screenshot.nix)。

剪贴板历史只由 Noctalia 管理；现有 Wayland/X11 桥接不是第二个历史后端，其退出与轮询策略按 [服务设计](service-policy.md) 核验。保留 WeChat/XWayland 与原生 Wayland 间文字、图片互通。锁屏和秘密复制行为先按锁定实现验证，不声称所有密码管理器内容都会自动排除；不输出剪贴板内容到测试日志。

## 终端、项目与远程工作

Kitty 新窗口默认进入普通 shell，不自动套 tmux。用户需要保持项目工作现场时显式运行 tmux；每个常用项目一个 session，window 表示编辑/构建/运行，pane 只用于同时观察。避免同时用 Kitty tab 和 tmux window 管同一项目。

| tmux 操作 | 入口（先按 Ctrl+a） |
|---|---|
| 左右 / 上下分屏 | `\|` / `-`，继承当前 pane cwd |
| pane 聚焦 | `h/j/k/l`（前缀绑定，无前缀 Alt 留给应用） |
| 放大 pane | `z`，沿用默认 |
| window 新建 / 前后 / 最近 / 按编号 | `c` / `n,p` / `Tab` / `1…9`；显式把最近窗口绑定为 `Tab`，让 `l` 专用于 pane 向右 |
| 复制模式 / 选区 / 复制 | `[` 后 `v`、`y`，沿用 vi 模式 |
| session/window/pane 搜索 | `F`，保留现有 tmux-fzf |
| 离开但不结束 | `d` |
| 重载 | `r` |

tmux 会话恢复继续保留布局与编辑会话，禁止保存 pane 滚屏文本。恢复不等于重启数据库、容器、SSH 或付费 AI 任务；不能把“恢复窗口”实现成无条件重放历史命令。见 [现有恢复设置](../aspects/command-line/tmux.nix)。

Zsh 的 `Ctrl+R` 由 Atuin 搜索本地命令历史，使用 compact 视图、全局默认筛选，并保留上箭头的原生 shell 搜索行为；候选需要再次按 Enter 才会执行。Atuin 同步与更新检查关闭。fzf 保留 `Ctrl+T` 文件选择和 `Alt+C` 目录选择。Atuin 数据库属于运行态用户数据，首次配置完成后如需导入旧历史，由用户在应用后显式执行；配置构建与隔离按键检查不会导入或读取真实历史。

项目的依赖、编译器和 SDK 版本由项目 `flake.nix`/`flake.lock` 拥有；全局只提供确认保留的基础工具和交互工具。direnv/nix-direnv 负责目录环境缓存：新的或变化的 `.envrc` 需用户信任，首次缺依赖时下载是正常行为，不承诺进入项目零等待。编辑器、语言服务器必须从项目 cwd/环境启动；桌面打开目录不能假装自动获得其 devShell。全局 clangd 用 PATH，项目可覆盖，已有语言接口不把所有工具写死成 store 路径。

远程默认在服务器内用 tmux 持续工作，笔记本只作 SSH 客户端。SSH 不嵌套自动启动 tmux；有意嵌套时文档说明如何发送前缀。服务器远程 workspace 不附带 GUI、Kitty 或本地剪贴板 daemon，参考 [服务器规划](server-plan.md)。

## 编辑器阅读与文件导航

正文默认开启按词边界的软折行，续行保留缩进；`Space u w` 切换当前窗口软折行，关闭后通过原生水平移动浏览。`Ctrl+D/U/F/B` 保留原生目标和计数，默认使用已有
180 ms 视口插值；共享 `reducedMotion` 为真时直接滚动，不影响滚动距离或光标位置。

文件导航由两个入口组成：`<leader>e` 打开 Snacks Explorer 侧栏，`-` 打开 Oil 可编辑父目录，
用于批量改名与目录操作；`<leader>fy` 打开常用的 Yazi 浮窗。Oil 删除只移入回收站，拒绝
覆盖已有目标，copy 使用独占创建；从回收站恢复同样先校验目标，永久 purge 禁止。具体文件
安全边界和实现见 [Neovim 执行记录](neovim-rebuild-execution.md)。

Snacks picker 保留常用文件搜索入口，并统一承担 grep、buffers、最近文件、帮助、符号、诊断、
keymaps、命令历史、项目和恢复上次 picker：`<leader>ff/fg/fb/fr/fh`、`fs/fS/fd/fk`、
`f:`、`f/`、`fp`。`<leader>gg` 打开 LazyGit；`<leader>st` 或 `<leader>xt` 搜索 Todo，
`[t` / `]t` 在 Todo 之间跳转。调试使用 F5/F10/F11/F12 与 `<leader>d*`，任务运行使用
`<leader>r*`。`<leader>rn` 保留 LSP 符号重命名，`<leader>fR` 是文件重命名；`zK` 现在执行
原生 `zo` 打开折叠。which-key 分组统一使用英文，完整映射见 [Neovim 键位表](neovim-rebuild-execution.md#键位)。

顶部标签在工具窗口聚焦时保留最近文档的选中状态；左键切换到正文窗口，中键/关闭按钮走原有
安全关闭流程。Explorer 保留侧栏窗口；没有正文窗口时新开一个 split。状态栏随窗口显示文档或
工具上下文；常规语言服务进度放在状态栏，并随任务完成清除，错误/警告与通知历史仍由原通知
机制提供。Neovim 第六轮尚未应用，运行状态与待验项见[执行记录](neovim-rebuild-execution.md)。

## 交互反馈与实现边界

成功截图/OCR给短通知，普通音量/亮度使用 Noctalia OSD；取消操作不发错误通知。权限、磁盘、网络等失败有可读错误及查看日志入口，通知不包含凭证。游戏全屏和屏幕分享按实际 shortcut inhibition/portal 行为验收，不擅自屏蔽全部保命键。

按键与帮助只维护一份实际动作数据，用当前 Mango renderer 生成配置和静态帮助；tmux/Neovim 的按键仍由各自功能拥有，只向帮助提供明确分组。无需建立跨应用按键解释器或焦点探测 daemon。新增帮助展示手段优先复用保留的软件，不能借此引进整套新 shell。

验收：检查同模式/公共模式按键冲突；真实终端中 Alt 字母、数字、Esc、中文输入正常；tmux 和 Neovim 层次独立；resize 重载后仍可退出；多显示器截图和窗口移动正确；路径参数保真；图形/CLI 默认编辑器各自正确；全屏 MC、鼠标捕获、Alt-Tab/工作区、退出游戏均做实机验证。自动测试不能替代这些 GUI 检查。

此前实现阶段只改声明和文档；用户随后 nr，本轮应用和实际验证按后续记录区分，不代表键盘、触控板、游戏或远程会话已全部验收。
mod 任务继续受保护，不注销 Mango 或终止业务。本轮明确获授权的 shell 交接、配置应用与
检查见[系统与编辑器记录](history/system-polish-execution.md)，不把早期未应用记录当作当前状态。

## 项目与长任务入口

启动器搜索“Nix 配置工作台”可打开真实项目目录中的终端；项目目录
不存在时报错，不创建或退回其他位置。命令行支持 `workspace-project list`、
`workspace-project dotfiles editor`、`workspace-project dotfiles files`。editor 使用 CLI
默认编辑器，首次进入目录视图；`--` 后的文件参数按 argv 传递。有 `.envrc` 时用
`direnv exec`，不自动 allow、不绕过信任失败，不自动运行构建或恢复历史命令。

启动器“长任务终端”及 `workspace-task -- 命令 参数` 仅在命令运行期间持有 sleep inhibitor，
结束后自动释放。它仍允许自动锁屏和关屏，不是后台常驻模式，也不能保证抵抗断电或强制
睡眠。`Super+Alt+I` / 面板咖啡是独立的 Noctalia 防空闲开关，会影响自动 idle actions；
不能把它当成对手动休眠或盖盖子行为的全面保护。两个入口不自动套在已有任务上。

`Super+Alt+D` 或右键铃铛切换勿扰，被隐藏的外部通知保留在 Noctalia 历史中，退出勿扰
不会重放旧弹窗。Kitty 有前台任务时关闭窗口会请求确认；tmux/编辑器不会被强制重载。

## 日常播放器与主题交接

mpv 使用 uosc 时间线/播放列表/菜单与 thumbfast 缩略图。空格暂停、左方向键后退；右方向键由 evafast 保留轻按跳转、长按临时加速。`Ctrl+1` 开启原 Anime4K HQ 链、`Ctrl+0` 关闭，默认不对所有视频套用 CNN。菜单删除使用垃圾桶，media 自行提供 trash-cli。

Yazi 主题由 HM 消费共享 OneDark palette，不再由 Noctalia yazi 模板写入。原公开主题在交接前备份，数据与历史保持原样；tmux/Kitty/Yazi 的已运行实例不会被强制重启，重新打开时读取新配置。具体运行证据见[系统界面记录](history/system-experience-execution.md)。

右下角鼠标热区已关闭；左下启动器热区保留。新登录环境的 `BAT_THEME=base16` 与 Bat/Delta
声明一致。旧桌面含 HM 已加载标记，新终端也可能继承旧值，完整重登录后刷新；
当前终端可用 `env BAT_THEME=base16 bat 文件` 临时采用新主题。
桌面会话的移除过程和应用状态见[Hyprland 移除记录](history/hyprland-removal-execution.md)。
另有用户明确选择的可选 dwm + Picom / 真 Xorg 会话，用于 QQ、腾讯会议原生共享；
登录选择、原生栏、菜单和不同于 Mango 的操作见 [Xorg 记录](xorg-desktop-execution.md)。

## 2026-10-20 增强

启动器输入 `/tr 文本` 翻译为中文，`/tr en 文本` 指定英文；查询使用 Google 在线服务。
项目入口的编辑器和目录可从 desktop actions 选择；明确启用 workspace 的项目还可用
`workspace-project dotfiles workspace`
建立/复用编辑器与两个 shell 的 tmux 布局，不自动构建、执行测试或信任 `.envrc`。
实现、验证和应用状态见[本轮记录](history/optimization-2026-10-20.md)。
