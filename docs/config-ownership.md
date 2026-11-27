---
summary: 每个配置文件、可变状态和秘密由谁写入，移除功能后留下什么
read_when: 改任何生成文件前、遇到文件被覆盖、迁移配置 writer
code: [aspects, inventory/hosts/nixos-btw/secrets.nix]
checks: []
---

# 配置、运行时状态与秘密的写入归属

本文记录源码声明的 writer。构建或求值不能证明文件、服务和权限已生效；排障时要核对真实文件、symlink、权限和进程。表中“待验”类说明写于当时，不代表现状。

归属依据是当前 aspect、inventory、`flake.lock` 锁定模块和可观察到的运行行为。Den 负责组合功能，不改变证据优先级。每个生成目标只保留一个 renderer；应用可变文件只由 feature 修改明确拥有的字段或标记块。配置迁移不删除项目、认证状态、历史、模型、容器卷或 VM 镜像。

## 当前声明归属

| 功能或路径 | 当前声明的唯一 owner / renderer | 可变状态与边界 |
|---|---|---|
| 外观数据 `host.appearance`、`user.appearance` | `aspects/appearance/appearance/onedark.nix` 提供 One Dark 精修语义颜色、字体、光标、图标主题和 `reducedMotion` 偏好；`aspects/appearance/appearance/contract.nix` 定义 host/user schema。 | 数据本身不安装应用或选择功能。当前 host 与 mayon 分别绑定同一 palette；动效偏好是声明式输入，不另写 GUI state。 |
| `~/.config/mango/config.conf`、Mango 快捷键说明 | 选择 `interactive-session` 后，`aspects/desktop/mango-session/mango.nix` 接线私有的 `mango/keybinds.nix` 和唯一窗口规则表 `mango/window-rules.nix`，配合锁定 Mango HM module 渲染完整配置；`~/.local/share/mango/keybindings.txt` 也由该 aspect 生成。 | 没有第二个 Mango 主题写入者，也不 include 额外颜色片段。配置为声明式输出；Mango 会话实际加载与快捷键手感仍待应用后核验。 |
| `~/.config/kitty/kitty.conf` | `aspects/cli/terminal/kitty.nix` 是唯一 HM renderer，生成完整 One Dark 配置和 ANSI 色。 | 没有第二个 Kitty 主题写入者。真实 Kitty parser / 主题应用情况需在新 generation 中复核。 |
| `~/Pictures/Wallpapers` | 用户数据；原 wallpaper feature 的 link farm 已随统一 shell 删除，Noctalia 壁纸面板直接选本地文件。 | 不自动迁移或删除用户图片；旧 `managed/`、`local/` 保留。 |
| 头像 | `aspects/appearance/avatar/` 的 `package.nix` 消费 host/user avatar identity 与 appearance palette，生成 PNG；`home.nix` 管理 HM 数据文件和缺失时 seed `.face`；选中的 avatar 经 quirk 贡献标记，Mango 的 `lockscreen-avatar.nix` 校验后渲染锁屏 sticker；`nixos.nix` 管理 `/etc/nix-dotfiles/mayon-avatar.png` 与 AccountsService 更新脚本。身份数据只在 host/user inventory binding 提供。 | `.face` 与 AccountsService `icons/mayon` 仅在缺失时 seed 到各自稳定路径，已有文件和软链保留；生成目标随 generation 更新。AccountsService `users/mayon` 只补 `[User]` 中缺失或空的 `Icon`，保留非空自定义值和其他字段，并拒绝写穿元数据/父目录软链。移除功能不删 `.face`、图标、AccountsService 用户文件或自定义值。 |
| 登录 greeter | `login-screen` feature 由 `aspects/desktop/greeter/greeter.nix` 生成 greetd 会话、sway 配置、gtkgreet CSS 和唯一的 `mango-login` 命令，消费 host appearance 与 display facts。 | 登录屏幕布局、缩放和认证流程仍待目标主机冷登录实测。 |
| Fcitx5 / Rime | `aspects/desktop/session-support/input-method.nix` 与 `rime/theme.nix` 渲染完整主题目录（INI 与六个 palette SVG）、两个 `.custom.yaml` 与两张公开专业词表；`rime/package.nix` 将固定 hash 的万象模型链接到包内 `share/rime-data`，不在用户目录另放同名模型。复合字典显式保留锁定上游五张中文表及主表正文，再补小型专业词表；`translator/user_dict = rime_ice`。 | 仅声明配置与公开词表，不拥有 `rime_ice.userdb`、同步数据、个人 `custom_phrase`、`user.yaml`、`installation.yaml` 或旧备份。部署交给 Fcitx5 内的 Rime，不并发用外部 deployer 打开真实学习库。词表维护见[说明](../aspects/desktop/session-support/rime/README.md)，部署/验收记录见[收尾记录](history/README.md)（原文 `panel-rime-execution.md`）。 |
| GTK 主题、字体、图标、光标与 GTK CSS | `aspects/desktop/session-support/gtk.nix` 由 HM 声明 adw-gtk3 theme、GTK2 Adwaita-dark 引擎及 One Dark roles、字体、WhiteSur-dark（蓝色文件夹）、Bibata-Modern-Ice 32 和 dconf 暗色偏好；`resources/gtk/gtk3.css` 与 `gtk4.css` 中的 palette 占位符在构建期替换后，由 HM 写成 `gtk-3.0/gtk.css` 与 `gtk-4.0/gtk.css`，这是唯一写入者。 | HM 不声明第二套 GTK CSS，也没有运行时模板引擎改写这两个文件。`gtk-qt-theme` 用真实 GTK3/GTK4 CSS provider 解析生成文件；当前 profile 和新 generation 实机效果仍待复验。 |
| `~/.config/qt6ct/qt6ct.conf`、`qt6ct/colors/one-dark.conf`、`qt6ct/qss/one-dark.qss` | `aspects/desktop/session-support/qt.nix` 由 HM 独占只读 QSS；qt6ct.conf 缺失时 seed Fusion、palette 图标名、正确 quoted 字体字符串、portal 文件选择器和 stylesheet 引用；session-support 同源投递 Qt QPA 插件搜索路径。激活只迁移完整旧/当前未引号默认字体、原 Papirus-Dark 默认图标，并向既有 QSettings stylesheet 列表追加缺失的 managed QSS 路径。palette 缺失时 seed 22 个公共 One Dark roles；该文件是 HM seed 的只读参考，qt6ct GUI 仍是运行时写入者。 | `Appearance/standard_dialogs=xdgdesktopportal` 由 activation 在已有文件上也维护；GUI 拥有其他设置，自定义字体/icon/style/stylesheet 顺序和未支持的合法 Qt 转义保守保留，重建会补回 managed QSS 引用；CRLF/幂等和真实 QSettings 读回有隔离检查。seed/迁移拒绝文件及父路径 symlink，不写穿用户链接。仅在私有无头会话运行 qt6ct GUI；未操作用户会话、启动用户服务或应用 generation。GUI 保存后重启读回仍待实机验收。同一 activation 还在 `qt5ct/qt5ct.conf` 缺失时 seed 同一 palette、Fusion、图标名和字体，供 Octave 这一个 Qt 5 应用读取；已有文件不覆盖。 |
| Firefox 包、策略与 profile UI | `aspects/apps/firefox` 提供 Firefox 包、扩展/主题策略、MIME scheme 和 UI seed；`seed-firefox-ui.py` 只更新默认 profile 的 `user.js` 与 `chrome/userChrome.css` 中仓库 marker block；palette CSS 在构建期由同一模板渲染，没有第二个运行时写入者。 | Firefox 自己的 profile、登录状态、其他偏好和 CSS 内容仍由应用/用户持有。脚本在目标文件或其直接父目录为 symlink、marker 不完整时拒绝处理。当前默认 profile 与 marker 结果尚未针对新 generation 核验。 |
| 默认工具 wrapper 与 MIME | `aspects/system/default-tools` 消费账号 binding 的 `defaultTools`，仅生成 terminal/editor/browser/file-manager wrapper、`TERMINAL/EDITOR/VISUAL/BROWSER` 和其拥有的 MIME（目录、文本、shell、HTTP(S)/HTML；Markdown 默认沿用此绑定）。`~/.local/share/applications/mimeapps.list` 也归它，并设 `force = true`：xdg-mime 与 MATLAB/LibreOffice 一类安装器会重写这个 data-home 副本，Home Manager 再备份时会撞上自己的旧 `.backup` 并中止整次 activation。 | 选择默认命令不会安装被引用应用。`guiTextEditor` 使用真实 desktop ID；PDF、图像、视频和专属 scheme 留给各应用 feature。`~/.config/mimeapps.list` 优先级更高，仍是声明式默认值的实际来源；被覆盖的 data-home 副本由 activation 重建，不保留应用写的关联。应以生成 profile 核实 ID 和 MIME，不依赖旧模块注释。 |
| herdr 配置与入口 | `aspects/cli/herdr/home.nix` 通过 HM 独占 `~/.config/herdr/config.toml` 和 desktop 入口，`pkgs.local.herdr` 保留原始别名，功能局部补丁只改焦点标签绘制。 | 不启用登录 daemon，不修改 tmux；herdr server 随用户启动按原生生命周期管理。项目、认证、终端历史和工作区状态不由 Nix 接管或清理；不通过 GUI 设置另写 HM 配置。 |
| Shell、tmux、Yazi 与工具 | `aspects/cli/shell` 拥有 Zsh、Git、direnv、nix-index、tmux、Yazi、sysinfo 和命令行工具声明。`TERMINAL/EDITOR/VISUAL/BROWSER` 的唯一数据源是 default-tools；交互会话只投递受限 session 环境。 | Yazi `theme.toml` 由 HM 使用共享 palette 渲染；原公开主题保留回退副本。Zsh history、tmux 持久 session、Yazi 数据和工具自身历史是用户数据，功能移除不清理。环境变量只将显式安全白名单镜像到 systemd user manager / compositor，不转发完整 home environment 或 secret。 |
| bat / delta 配色与缓存 | `aspects/cli/shell/onedark-bat.nix` 从 palette 生成共享 `.tmTheme` 与构建期预编译 cache；HM 写 `bat/config`、`bat/themes/One Dark.tmTheme` 和 Git delta 配置，session `BAT_CACHE_PATH` 指向只读 store；delta 专用 wrapper 将该进程的 `XDG_CACHE_HOME` 指向含同一缓存链接的 store 根目录（0.19.2 忽略 BAT_CACHE_PATH）。HM batCache 激活为空。 | 现有用户 cache 不清理；delta 与 bat 读取同一套 themes.bin/syntaxes.bin。新增主题/语法应纳入同一构建期缓存配方，不恢复登录时重建。 |
| CLI 外观文件 | `tools.nix` 拥有 `eza/theme.yml`、`glow/glow.yml`、`glow/onedark.json`、`tealdeer/config.toml`；`sysinfo.nix` 拥有 fastfetch 配置、`btop/btop.conf` 与 `btop/themes/One Dark.theme`。 | CLI 与桌面统一选择 HM 生成的 One Dark；btop 配置和主题由 HM 独占，没有模板引擎 apply/undo。不清理用户历史或其他主题。tealdeer 的下载页面 cache 归工具运行时，自动更新仅在使用时进行；不清理历史、模型或已有缓存。 |
| Atuin 配置与历史 | `aspects/cli/shell/zsh.nix` 通过锁定 Home Manager `programs.atuin` 写入 Atuin 配置和由外观 palette 派生的 `onedark` 主题，并启用 Zsh 集成。 | `~/.local/share/atuin/` 中的本地数据库、日志和同步状态归 Atuin/用户运行时管理；当前关闭同步与更新检查。升级或移除声明不删除数据库，不自动导入 `~/.zsh_history`；需要导入时由用户在配置应用后显式执行。 |
| Neovim、VS Code、JetBrains | `aspects/dev/neovim/` 拥有原生 Lua、插件、parser、片段、查询、测试和 package wrapper；HM 只链接 `init.lua`，语言贡献由 `aspects/dev/languages` 合并后作为生成数据交给单一 Lua consumer。VS Code 与 JetBrains 应用/包装由 `aspects/dev` 的相应 feature 提供。 | 插件数据、编辑器历史、项目和应用登录状态留在用户数据。配置构建检查不等同于 Mango 桌面中的字体、弹窗或 LSP 实机验证。 |
| `~/.config/kdeglobals`、`~/.local/share/color-schemes/NixDotfilesOneDark.colors` | `aspects/desktop/session-support/kde.nix` 由 HM 独占；从共享 appearance 生成 KDE ColorScheme、WhiteSur-circle-dark 图标和 Fusion 设置，避免 KDE 组件回到亮色默认。 | 声明式只读输出；应用自绘主题仍归应用。移除 feature 撤回声明，不删除应用数据。 |
| Prism One Dark 主题 | gaming 在用户提供 appearance 时通过 HM 管理 `~/.local/share/PrismLauncher/themes/OneDark/theme.json` 与 `themeStyle.qss`；复用 session-support 的公开 `qt-style.nix` 工厂与共享 QSS，并追加 Prism 专用控件样式；另管理 `catpacks/NixDotfilesPrism/` 背景与 `iconthemes/NixDotfilesPrism/` 图标资源。 | Prism 自带主题会覆盖 qt6ct 样式，因此在 Settings → Appearance → Theme 中选择 `One Dark`。`ApplicationTheme`、`BackgroundCat`、`IconTheme`、Java/内存设置、账号、实例、模组、存档均保留给 Prism；移除 feature 仅撤回主题及图形资源，不修改所选主题键。 |
| `~/Templates/blank.{txt,md,py,sh,lua,nix}` | `aspects/apps/file-manager/templates.nix` 仅对缺失文件 seed 空白内容。 | 之后归用户；已有文件、悬空文件软链以及 Templates 目录软链均保留。移除 feature 不删除模板。 |
| `~/.config/onlyoffice/DesktopEditors.conf` | documents 不再安装 OnlyOffice，也不再 seed 或管理此文件。 | 移除声明不会删除已有配置文件、软链或文档；该路径留作用户数据。 |
| 系统 profile 的 `share/dbus-1/services/org.freedesktop.FileManager1.service` | file-manager 的 host Thunar 包提供唯一规范服务文件；HM 不再安装重复包或生成本地服务。 | 与 `inode/directory=thunar.desktop` 配合，Exec 指向带插件 Thunar；移除 feature 仅撤回声明，保留应用状态。 |
| Thunar actions 与快捷键 | `aspects/apps/file-manager/thunar-actions.nix` 生成完整 `~/.config/Thunar/uca.xml`；activation 只维护 `accels.scm` 中仓库 `copy-image-as-png-1` 的一行。`thunar-terminal.nix` 生成绝对路径 helper 与 XFCE terminal helper 选择；动作经 workspace terminal/editor 或显式包路径运行。 | `uca.xml` 不再由 Thunar GUI 保存；accels 其余行归 Thunar/用户。首次交接前须检查旧 action、ID 和 accel 行。 |
| mark-shot 配置 | 程序自己读写 `~/.config/mark-shot/config.toml`。没有 TOML 时继续读已有 `config.json`。Mango 窗口矩形由程序内的 `mmsg` 查询产生，激活脚本不再改写 `windowDetection.command`。 | 配置、历史和已保存图片归程序与用户。移除安装不删除这些文件。 |
| `~/.config/noctalia/config.toml`、`palettes/one-dark.json` | `aspects/desktop/noctalia-shell/noctalia.nix` 是唯一声明写入者；两个会话共用。 | 移除 noctalia-shell feature 后撤回声明；`~/.local/state/noctalia` 与缓存是用户数据。 |
| `~/.config/noctalia/` 运行时状态 | Noctalia 进程写入设置/历史；仓库不手写运行时文件。 | 用户数据，不清理、不迁移。 |
| 剪贴板与通知 | `noctalia.service` 是唯一 `org.freedesktop.Notifications` 与剪贴板历史 owner；`clipboard-bridge.service` 负责 X11↔Wayland。 | 通知历史与剪贴板历史是 Noctalia 运行时状态，配置不清理已弹出消息。 |
| 壁纸/锁屏/OSD | 全部由 `noctalia.service` 拥有，不再有单独的 swaybg/sweetbgd/Matuwall/swaylock/swayidle/swayosd 配置或 unit。 | 移除 feature 后撤回声明。 |
| 用户 clipboard 与截图状态 | 交互会话声明三个 target 上的 `clipboard-bridge.service`；`mark-shot` 查询 `mmsg` 取窗口矩形，全屏/区域截图走 Noctalia IPC，OCR 脚本用 grim/slurp。 | 截图与 OCR 输出是用户状态；仓库不记录剪贴板内容。 |
| 自写 TUI | `packages/mayon-tui` 独占程序源码、共享 UI 与 palette 构建；laptop-network 注册的 `clash-tui` 安装公开 clash 输出；container-client、port-tools、embedded-workbench、keys-mayon 共同选择 mayon-tools 功能安装 tools 输出；serial/keys 源码和 voice dashboard 均在该工作区，桌面拥有快捷键与窗口规则。 | Clash native 独占 `~/.local/share/mayon-clash/` 的 subscriptions.toml、订阅缓存、settings.toml、runtime/上一份配置（文件0600、目录0700）；mihomo 拥有 Geo/cache/providers 运行数据。可选 TUI 偏好仍归用户只读消费。日志仅内存。Docker 数据仍归 Docker/用户；确认操作可删指定容器/镜像，卷需二次确认且不自动清理。端口信号只允许当前 UID 且复核启动时间/pidfd 的进程。移除工具仅撤回二进制，不清理应用数据。 |
| rootless Docker | `local-containers` 将 Docker CLI、shell 与 systemd 的 DOCKER_HOST、选定账号的 user daemon 和 weekly `docker builder prune -f --filter until=168h` timer 绑定在一起；host support 复用锁定 NixOS rootless unit 的配置并取消全局 user-unit 自动拉起。 | Rootless Docker 数据目录、容器、镜像和 named volumes 留给 Docker/用户；自动 prune 仅清理旧构建缓存，不再清理停止容器及其可写层。运行态尚未专项核验，不声称 daemon/timer 已正常运行或数据已迁移。变更服务前核验真实 `docker info` 的 data-root、unit 和卷。 |
| 本机 VM | `local-virtual-machines` 选择后安装 virt-manager、配置 `qemu:///system`、授予 `libvirtd`/`kvm` 组，并由 host support 配置 QEMU/KVM、swtpm 和 SPICE USB redirection。libvirtd 通过 socket 激活；`libvirt-guests` 被禁用。 | VM 镜像、快照、存储池和 guest state 归 libvirt/用户，当前 aspect 不迁移或删除它们。新组实际权限、socket activation 和存储池仍待专项核验。 |
| Legion 电池养护 | `legion-laptop` host 声明 `legion-conservation` 组及 ideapad_acpi sysfs 属性 udev 权限；`legion-laptop-user` 的 user class 授予所选账号并安装 `legion-conservation status|toggle`。桌面仅调用 CLI，不获取管理权限。 | `/sys/bus/platform/drivers/ideapad_acpi/*/conservation_mode` 由内核/固件拥有；只有用户点击才写0/1，构建与激活不写养护值。移除配置保留固件现状；权限撤销需设备重建/重启、组变化需刷新登录。无额外 daemon。 |
| 主机图形服务与权限 | `graphical-session-support-host` 拥有基础 portal、PipeWire、polkit 和字体；`interactive-session-host` 拥有 Mango 与其 wlroots 路由；`noctalia-shell/services.nix` 在三个 session target 上启动唯一的 polkit authentication agent、Noctalia 和 clipboard bridge。用户 feature 负责自己的 session service 和账号组授权。 | 安装包不等于服务运行或权限生效。需在应用后核验最终 unit target、agent 唯一性、groups、udev tags/mode 和 logind ACL；不从配置求值推断。 |
| sops 凭据与 shell 消费 | `inventory/hosts/nixos-btw/secrets.nix` 指定 SSH host key 解密密文，deepseek/github secret owner 为 mayon；Nix access-token fragment 以运行时 SOPS template 写入，owner mayon、mode `0400` 并由 Nix 配置 `!include`。secret name 与导出变量由 `inventory/hosts/nixos-btw/users/mayon.nix` 数据提供；`aspects/cli/shell/zsh.nix` 仅在运行时读秘密路径。 | 明文不得进入 Nix 字符串、日志、生成配置或 store。密文文件仍为输入；构建不证明本机 age key、解密结果、owner/mode 或撤销行为有效，须现场核验且不得输出 secret 内容。 |

## 迁移与回退

每个功能按完整 owner 边界交接。先盘点目标账号/主机上的路径类型、realpath、owner/group/mode、校验和、XDG 根目录、关联应用/进程及运行服务；state 和凭据只记录必要 schema/元数据，不把敏感内容放入报告。然后禁用旧 writer，再启用新 writer。不要让两个程序交替写同一目标。

对声明式生成文件保留权限受控、Git/Nix 源之外的可回退副本，并确认是否有手工修改。对可变文件仅迁移 owner 明确拥有的键或 marker block；发现无法表示的手工内容时，保存两份并按最小差异处理。

发布前先完成 Nix 求值、目标构建和相应应用 parser 检查；需要跨文件时按依赖顺序分别发布，不能声称多文件原子切换。失败回退时先停用新 writer，再按备份恢复原文件类型、权限和 symlink，并恢复旧配置入口；之后重新加载相关应用/服务。备份保留到新 owner 在目标主机实机验证并确认回退可用。不得因为配置 owner 改变而自动清理 state、缓存、历史、认证、项目、模型、容器卷或 VM 镜像。

## 验证状态与现场要求

源码组合、生成配置、构建的 unit 和隔离 fixture 只能证明声明/构建层行为；历次授权与操作只对对应历史记录有效。桌面 shell 移除后，会话组件由各自单元重新拉起；其他文件与应用仍须逐项核实，不能由一次 service active 推断全部数据已迁移或所有 writer 交接完成。

在实际应用后，逐路径检查 Home Manager generation、symlink/普通文件、mode、owner、会话 unit 前后关系、环境变量、MIME/desktop IDs、最终组与 udev/ACL。再冷启动相关应用验证 Kitty parser、Mango config、GTK/Qt palette、Firefox managed block、Thunar 保存行为、Docker daemon/timer 和 libvirt socket/存储池。完成前保留回退副本；没有实机证据的项持续标为“待现场验证”。

相关约束与流程见 [架构设计](architecture.md)、[桌面视觉设计](desktop.md)、[操作方式](keymap.md)、[服务策略](service-policy.md)、[服务器规划](server-plan.md)、[执行交接](history/README.md)（原文 `execution-handoff.md`） 和 [Den 执行记录](history/README.md)（原文 `den-execution.md`）。

D-Bus 服务文件：FileManager1 的唯一声明改由 file-manager 的 host Thunar 包拥有，撤回 HM 的重复 Thunar 包与 per-user service。session-support 通过上游工厂生成并合并 `/etc/dbus-1` 的显式服务注册，保持 policy include 与标准用户 XDG 服务发现。上述移除仅涉及声明式服务文件，不删除 keyring、文件管理器状态、缩略图、通知历史或用户数据。

原生 Clash 声明：[laptop-network](../aspects/network/laptop-network/README.md)
拥有无 boot wants 的 `mayon-clash.service` 和绑定用户的单元专属 polkit。Nix 不渲染
订阅或 mutable 配置。settings.toml 中已有 baseline 继续使用，缺失时回退内置默认；
TUI 与 CLI 共用 flock、临时文件校验、fsync/rename、
失败回滚。跨文件不是掉电原子事务，`config.previous.yaml` 保留回退配置。
Geo 从锁定 store 资源复制后可更新；服务只额外写入 native 数据目录和 systemd
分配的 runtime。mihomo socket 自身为0666，父目录0700/绑定用户是访问边界。
旧 GUI 原文件、增强脚本、登录状态与 native 数据在移除 feature 后均保留。
旧 GUI 数据含订阅，用户可自行决定手动删除；仓库不执行清理。
