# 配置、运行时状态与秘密的写入归属

本文记录当前 Den 源码声明的 writer，以及应用配置、可变状态和秘密之间的边界。用户已应用 Den 配置；本轮又授权进一步优化及 nr，实际运行交接见[当前应用记录](system-polish-execution.md)。构建或求值不能证明全部文件、服务和权限都已生效；仍按目标路径核对真实文件、symlink、权限、进程和应用状态。

归属依据是当前 aspect、inventory、`flake.lock` 锁定模块和可观察到的运行行为。Den 负责组合功能，不改变证据优先级。每个生成目标只保留一个 renderer；应用可变文件只由 feature 修改明确拥有的字段或标记块。配置迁移不删除项目、认证状态、历史、模型、容器卷或 VM 镜像。

## 当前声明归属

| 功能或路径 | 当前声明的唯一 owner / renderer | 可变状态与边界 |
|---|---|---|
| 外观数据 `host.appearance`、`user.appearance` | `aspects/appearance/onedark-darker.nix` 提供 One Dark Darker 语义颜色、字体、光标、图标主题和 `reducedMotion` 偏好；具体消费者由 `aspects/appearance` schema 接收。 | 数据本身不安装应用或选择功能。当前 host 与 mayon 分别绑定同一 palette；动效偏好是声明式输入，不另写 GUI state。 |
| `~/.config/mango/config.conf`、Mango 快捷键说明 | 选择 `interactive-session` 后，`aspects/interactive-session/mango.nix` 配合锁定 Mango HM module 渲染完整配置；`~/.local/share/mango/keybindings.txt` 也由该 aspect 生成。 | Noctalia 不生成 Mango 主题片段，也不写入或 include `noctalia-colors.conf`。配置为声明式输出；Mango 会话实际加载与快捷键手感仍待应用后核验。 |
| dwm / Xorg 配置与会话 | `xorg-session` 拥有 Nix 构建的 dwm、`~/.local/share/nix-dotfiles/xorg-session`、Picom/Dunst、dmenu wrapper 配置和 Xorg 专属 units；宿主安装唯一的 `xorg-dwm.desktop`。 | j4 的应用使用频次属于用户状态，保留而不托管；不托管用户 `.xinitrc`；不安装第二份未配置 dwm。runtime PID 记录只在当前用户的私有 runtime 目录，退出清除。详见 [Xorg 记录](xorg-desktop-execution.md)。 |
| CopyQ 数据与 X11 认证 | CopyQ 历史、应用账户及 `.Xauthority` 由应用/Xorg 管理；Nix 只启动会话服务。 | 不复制、输出、写入 store 或清除这些用户数据；不把构建当成共享通话验收。 |
| `~/.config/kitty/kitty.conf` | `aspects/command-line/kitty.nix` 是唯一 HM renderer，生成完整 One Dark Darker 配置和 ANSI 色。 | Noctalia Kitty builtin/template 不再启用。不存在由 Nix stub 与 Noctalia 主题文件拼装的当前声明。真实 Kitty parser / 主题应用情况需在新 generation 中复核。 |
| `~/.config/noctalia/config.toml` 与 custom palette | `aspects/interactive-session/noctalia.nix` 通过锁定 HM module 生成配置和 `One-Dark-Darker` palette；同一 aspect 生成 bar、launcher、widget、plugin、wallpaper、lockscreen 等声明。 | GUI 自建 palette 的写入不受支持，应在共享 palette 声明修改。GUI sidecar `~/.local/state/noctalia/settings.toml` 仍是 Noctalia 可变状态，不由 HM 整文件接管。插件运行数据、历史和其他 state 保留给应用。 |
| 登录 greeter | `login-screen` feature 由 `aspects/interactive-session/greeter.nix` 生成 NixOS greeter 配置，消费 host appearance 与 display facts。 | 声明已随系统应用；登录屏幕布局、缩放和认证流程仍待目标主机冷登录实测。 |
| Fcitx5 / Rime | `aspects/interactive-session/input-method.nix` 渲染主题、两个 `.custom.yaml` 与两张公开专业词表。复合字典显式保留锁定上游五张中文表及主表正文，再补小型专业词表；`translator/user_dict = rime_ice`。 | 仅声明配置与公开词表，不拥有 `rime_ice.userdb`、同步数据、个人 `custom_phrase`、`user.yaml`、`installation.yaml` 或旧备份。部署交给 Fcitx5 内的 Rime，不并发用外部 deployer 打开真实学习库。词表维护见[说明](../aspects/interactive-session/rime/README.md)，本轮部署/验收见[收尾记录](panel-rime-execution.md)。 |
| Noctalia sidecar 中与 Nix 冲突的公开设置 | Noctalia user service 的 `ExecStartPre` 调用 `aspects/interactive-session/resources/reconcile-overrides.py`。它按生成的公开设置树找出对应叶路径，并处理旧 `theme.templates.user.noctalia-mango` 路径。 | 只移除这些公开键，不重写整份用户 state；数组/非表叶按完整叶值处理，未知键与旁边设置保留。只备份被移除的 path/value JSON patch，备份目录 `0700`、文件 `0600`，不复制整份 sidecar。拒绝 symlink、坏 TOML、同 UID 的活动 `noctalia` writer 和检测到的并发变更。首次成功交接已发生：核实唯一旧 shell 的 executable/UID/start-time 并绑定 pidfd，仅对它发 SIGTERM、等退出和 writer scan 为空，再清失败状态并启动 managed unit；无需退出 Mango。不得对会话或进程组发信号，guard 继续拒绝活 writer。 |
| GTK 主题、字体、图标、光标与 GTK CSS | `aspects/interactive-session/gtk.nix` 由 HM 声明 GTK theme、字体、Papirus、Bibata cursor 和 dconf 暗色偏好；Noctalia GTK3/GTK4 templates 在运行时拥有其生成 CSS 与 import hook。 | HM 不声明第二套 GTK CSS。apply/undo、当前 profile 和 CSS 中既有手工内容尚未在新 generation 实机检查。 |
| `~/.config/qt6ct/qt6ct.conf`、`qt6ct/colors/noctalia.conf` | `aspects/interactive-session/qt.nix` 仅在 `qt6ct.conf` 不存在时 seed 字体、图标、Fusion 和 palette 路径；之后由 qt6ct GUI 拥有。Noctalia Qt template 运行时生成 palette 文件。 | seed 不覆盖已存在 GUI 设置。首次 seed、GUI 保存与重启读回尚未在新 generation 核验。 |
| Noctalia 模板集成 | 只在相关功能被用户 binding 选中时贡献对应集成：command-line 选择 btop，Yazi 主题由 HM 独占，编辑器选择 vscode，documents 选择 obsidian/zathura，Firefox 选择 Firefox CSS。GTK/Qt 由交互会话提供。 | Kitty 和 Mango 不属于 Noctalia integration。集成 template 的最终应用效果需逐应用在新 generation 验证。 |
| Firefox 包、策略与 profile UI | `aspects/firefox` 提供 Firefox 包、扩展/主题策略、MIME scheme 和 UI seed；`seed-firefox-ui.py` 只更新默认 profile 的 `user.js` 与 `chrome/userChrome.css` 中仓库 marker block。Noctalia（仅 Firefox feature 选择后）生成 cache CSS，并由 post-hook 将 palette CSS 合并到 Firefox managed block。 | Firefox 自己的 profile、登录状态、其他偏好和 CSS 内容仍由应用/用户持有。脚本在目标文件或其直接父目录为 symlink、marker 不完整时拒绝处理。当前默认 profile、marker 和运行时模板结果尚未针对新 generation 核验。 |
| 默认工具 wrapper 与 MIME | `aspects/default-tools` 消费账号 binding 的 `defaultTools`，仅生成 terminal/editor/browser/file-manager wrapper、`TERMINAL/EDITOR/VISUAL/BROWSER` 和其拥有的 MIME（目录、文本、Markdown、shell、HTTP(S)/HTML）。 | 选择默认命令不会安装被引用应用。`guiTextEditor` 使用真实 desktop ID；PDF、图像、视频和专属 scheme 留给各应用 feature。应以生成 profile 核实 ID 和 MIME，不依赖旧模块注释。 |
| Shell、tmux、Yazi 与工具 | `aspects/command-line` 拥有 Zsh、Git、direnv、nix-index、tmux、Yazi、sysinfo 和命令行工具声明。`TERMINAL/EDITOR/VISUAL/BROWSER` 的唯一数据源是 default-tools；交互会话只投递受限 session 环境。 | Yazi `theme.toml` 现由 HM 使用共享 palette 渲染，退出 Noctalia 的 yazi 模板；原公开主题保留回退副本。Zsh history、tmux 持久 session、Yazi 数据和工具自身历史是用户数据，功能移除不清理。环境变量只将显式安全白名单镜像到 systemd user manager / compositor，不转发完整 home environment 或 secret。 |
| Neovim、VS Code、JetBrains | `aspects/editing/neovim/` 拥有原生 Lua、插件、parser、片段、查询、测试和 package wrapper；HM 只链接 `init.lua`，语言贡献由 `aspects/languages` 合并后作为生成数据交给单一 Lua consumer。VS Code 与 JetBrains 应用/包装由 `aspects/editing` 的相应 feature 提供。 | 插件数据、编辑器历史、项目和应用登录状态留在用户数据。配置构建检查不等同于 Mango 桌面中的字体、弹窗或 LSP 实机验证。 |
| Thunar actions 与快捷键 | `aspects/file-manager/thunar-actions.nix` 生成完整 `~/.config/Thunar/uca.xml`；activation 只维护 `accels.scm` 中仓库 `copy-image-as-png-1` 的一行。`thunar-terminal.nix` 生成 helper 与 XFCE terminal helper 选择。 | `uca.xml` 不再由 Thunar GUI 保存；accels 其余行归 Thunar/用户。首次交接前须检查旧 action、ID 和 accel 行。 |
| mark-shot 配置 | `aspects/interactive-session/screenshot.nix` 的 activation 将 `~/.config/mark-shot/config.json` 的 `windowDetection.command` 指向 Mango 窗口检测 helper。 | mark-shot 对其他 JSON 设置拥有权。patch 应保持幂等并保留其余字段；实际既有文件尚未在新 generation 检查。 |
| 用户 clipboard 与截图状态 | 交互会话声明 Mango session target 上的 Wayland/X11 clipboard bridge；截图使用 Mango 窗口检测 helper。Noctalia 原生 clipboard 功能由 Noctalia 自身管理。 | Noctalia 的剪贴板历史与应用数据是用户 state；配置不执行清空。service unit 构建/求值不能证明会话启动顺序或剪贴板双向传输有效。 |
| rootless Docker | `local-containers` 将 Docker CLI、shell 与 systemd 的 DOCKER_HOST、选定账号的 user daemon 和 weekly `docker system prune -f` timer 绑定在一起；host support 复用锁定 NixOS rootless unit 的配置并取消全局 user-unit 自动拉起。 | Rootless Docker 数据目录、容器、镜像和 named volumes 留给 Docker/用户；prune 不带 `--volumes`。运行态尚未专项核验，不声称 daemon/timer 已正常运行或数据已迁移。变更服务前核验真实 `docker info` 的 data-root、unit 和卷。 |
| 本机 VM | `local-virtual-machines` 选择后安装 virt-manager、配置 `qemu:///system`、授予 `libvirtd`/`kvm` 组，并由 host support 配置 QEMU/KVM、swtpm 和 SPICE USB redirection。libvirtd 通过 socket 激活；`libvirt-guests` 被禁用。 | VM 镜像、快照、存储池和 guest state 归 libvirt/用户，当前 aspect 不迁移或删除它们。新组实际权限、socket activation 和存储池仍待专项核验。 |
| 主机图形服务与权限 | `interactive-session` 的具名 host support 配置 Mango、portal、PipeWire、polkit policy 和字体；Noctalia 负责选中图形会话中的认证 agent。用户 feature 负责自己的 session service 和账号组授权。 | 安装包不等于服务运行或权限生效。需在应用后核验最终 unit target、agent 唯一性、groups、udev tags/mode 和 logind ACL；不从配置求值推断。 |
| sops 凭据与 shell 消费 | `inventory/hosts/nixos-btw/credentials.nix` 指定 SSH host key 解密密文，deepseek/github secret owner 为 mayon；Nix access-token fragment 以运行时 SOPS template 写入，owner mayon、mode `0400` 并由 Nix 配置 `!include`。`accounts.nix` 的 Zsh 初始化仅在运行时读取 `/run/secrets/deepseek-api-key`。 | 明文不得进入 Nix 字符串、日志、生成配置或 store。密文文件仍为输入；构建不证明本机 age key、解密结果、owner/mode 或撤销行为有效，须现场核验且不得输出 secret 内容。 |

## 迁移与回退

每个功能按完整 owner 边界交接。先盘点目标账号/主机上的路径类型、realpath、owner/group/mode、校验和、XDG 根目录、关联应用/进程及运行服务；state 和凭据只记录必要 schema/元数据，不把敏感内容放入报告。然后禁用旧 writer，再启用新 writer。不要让两个程序交替写同一目标。

对声明式生成文件保留权限受控、Git/Nix 源之外的可回退副本，并确认是否有手工修改。对可变文件仅迁移 owner 明确拥有的键或 marker block；发现无法表示的手工内容时，保存两份并按最小差异处理。`reconcile-overrides.py` 的 sidecar patch 是有限例外：它只备份将移除的公开 path/value，不备份整份 Noctalia state，也不操作秘密。

发布前先完成 Nix 求值、目标构建和相应应用 parser 检查；需要跨文件时按依赖顺序分别发布，不能声称多文件原子切换。失败回退时先停用新 writer，再按备份恢复原文件类型、权限和 symlink，并恢复旧配置入口；之后重新加载相关应用/服务。备份保留到新 owner 在目标主机实机验证并确认回退可用。不得因为配置 owner 改变而自动清理 state、缓存、历史、认证、项目、模型、容器卷或 VM 镜像。

## 验证状态与现场要求

本次 Den 改造可验证源码组合、生成配置、构建的 unit 和隔离 fixture；这些只能证明声明/构建层行为。此前实现任务未应用系统；用户随后自行 nr，本轮又授权主代理应用。Noctalia sidecar helper 已随 managed service 成功运行，旧 shell 的优雅交接已单独验证；其他文件与应用仍须逐项核实，不能由一次 service active 推断全部数据已迁移或所有 writer 交接完成。

在实际应用后，逐路径检查 Home Manager generation、symlink/普通文件、mode、owner、Noctalia unit 前后关系、环境变量、MIME/desktop IDs、最终组与 udev/ACL。再冷启动相关应用验证 Kitty parser、Mango config、Noctalia theme apply/undo、GTK/Qt palette、Firefox managed block、Thunar 保存行为、Docker daemon/timer 和 libvirt socket/存储池。完成前保留回退副本；没有实机证据的项持续标为“待现场验证”。

相关约束与流程见 [架构设计](architecture-design.md)、[桌面视觉设计](desktop-design.md)、[操作方式](workflow-design.md)、[服务策略](service-policy.md)、[服务器规划](server-plan.md)、[执行交接](execution-handoff.md) 和 [Den 执行记录](den-execution.md)。
