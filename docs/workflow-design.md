# 操作方式设计

状态：2026-10-18 的操作设计已在 Den 配置实现，尚未应用系统。按键/argv/cwd、tmux 键表及编辑器的隔离检查见 [实施记录](den-execution.md)；实际 GUI、文件管理器和项目交互仍待验收。

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

| 操作 | 目标按键 | 目标变化 |
|---|---|---|
| 终端 / 文件 / 浏览器 | `Super+Enter` / `Super+E` / `Super+B` | 调用统一默认工具，禁止各入口独立硬编码应用 |
| 临时终端 | `Super+Shift+Enter` | 保留命名 scratchpad；使用 Kitty 实现所需 class，不塞进通用 terminal 协议 |
| 控制中心 / 剪贴板 | `Super+S` / `Super+V` | 保留 Noctalia 单一入口 |
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
| 操作帮助 | `Super+F1` | 新增计划：显示按分组整理的当前有效按键；先核验锁定按键解析及可用展示入口 |

工作区仅作建议用途：1 开发、2 浏览、3 通讯、4 文档、5 专业工具、6 媒体、7 虚拟化、8 游戏、9 临时。不强制按 app-id 自动搬走窗口；多项目、多个浏览器与临时用途不受限。显示器使用各自实际输出事实；不得把笔记本屏幕名写成通用协议默认值。

现有进阶操作（master 数量/比例、scroller 比例、隐藏边距、特定显示器开关等）在首轮迁移保留，归入帮助的进阶分组；只对重复或冲突的入口去重，禁止因未列入主表就静默删除。完整来源是 [Mango 配置](../aspects/interactive-session/mango.nix)。

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

| tmux 操作 | 目标入口（先按 Ctrl+a） |
|---|---|
| 左右 / 上下分屏 | `\|` / `-`，继承当前 pane cwd |
| pane 聚焦 | `h/j/k/l`（新增前缀绑定，替代无前缀 Alt） |
| 放大 pane | `z`，沿用默认 |
| window 新建 / 前后 / 最近 / 按编号 | `c` / `n,p` / `Tab` / `1…9`；显式把最近窗口绑定为 `Tab`，让 `l` 专用于 pane 向右 |
| 复制模式 / 选区 / 复制 | `[` 后 `v`、`y`，沿用 vi 模式 |
| session/window/pane 搜索 | `F`，保留现有 tmux-fzf |
| 离开但不结束 | `d` |
| 重载 | `r` |

tmux 会话恢复继续保留布局与编辑会话，禁止保存 pane 滚屏文本。恢复不等于重启数据库、容器、SSH 或付费 AI 任务；不能把“恢复窗口”实现成无条件重放历史命令。见 [现有恢复设置](../aspects/command-line/tmux.nix)。

项目的依赖、编译器和 SDK 版本由项目 `flake.nix`/`flake.lock` 拥有；全局只提供确认保留的基础工具和交互工具。direnv/nix-direnv 负责目录环境缓存：新的或变化的 `.envrc` 需用户信任，首次缺依赖时下载是正常行为，不承诺进入项目零等待。编辑器、语言服务器必须从项目 cwd/环境启动；桌面打开目录不能假装自动获得其 devShell。全局 clangd 用 PATH，项目可覆盖，已有语言接口不把所有工具写死成 store 路径。

远程默认在服务器内用 tmux 持续工作，笔记本只作 SSH 客户端。SSH 不嵌套自动启动 tmux；有意嵌套时文档说明如何发送前缀。服务器远程 workspace 不附带 GUI、Kitty 或本地剪贴板 daemon，参考 [服务器规划](server-plan.md)。

## 交互反馈与实现边界

成功截图/OCR给短通知，普通音量/亮度使用 Noctalia OSD；取消操作不发错误通知。权限、磁盘、网络等失败有可读错误及查看日志入口，通知不包含凭证。游戏全屏和屏幕分享按实际 shortcut inhibition/portal 行为验收，不擅自屏蔽全部保命键。

按键与帮助只维护一份实际动作数据，用当前 Mango renderer 生成配置和静态帮助；tmux/Neovim 的按键仍由各自功能拥有，只向帮助提供明确分组。无需建立跨应用按键解释器或焦点探测 daemon。新增帮助展示手段优先复用保留的软件，不能借此引进整套新 shell。

验收：检查同模式/公共模式按键冲突；真实终端中 Alt 字母、数字、Esc、中文输入正常；tmux 和 Neovim 层次独立；resize 重载后仍可退出；多显示器截图和窗口移动正确；路径参数保真；图形/CLI 默认编辑器各自正确；全屏 MC、鼠标捕获、Alt-Tab/工作区、退出游戏均做实机验证。自动测试不能替代这些 GUI 检查。

本文只核对现有源码并规定迁移目标，未进行键盘、触控板、游戏或远程会话运行验证。
