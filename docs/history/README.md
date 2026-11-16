# 执行记录

本目录只保留这份索引，按月记录做过什么。每条的完整原文（含命令输出、截图路径、generation 与当时的“未应用”结论）在 Git 标签 `history-archive-2026-11-06` 里：

```sh
git show history-archive-2026-11-06:docs/history/<文件名>
git show history-archive-2026-11-06 --stat -- docs/history   # 列出全部原文件
```

规则：

- 这里写**过程与结论**，顶层文档写现行事实；同一事实不在两处维护。
- 新记录追加到对应月份的表格末尾：日期、做了什么、结果或证据层级（求值 / 构建 / 应用 / 实机）。需要长篇原文时写进提交说明，而不是新建文件。
- 旧记录里的 generation、store 路径、版本号与“未应用”只对应当时的提交，不代表现状。

2026-10-31 顶层文档改名对照（旧原文中的链接可能失效）：`architecture-design`→`architecture`，`workflow-design`→`keymap`，`visual-design`→`visual`，`desktop-design`→`desktop`，`application-review`→`apps`，`neovim-rebuild-execution`→`neovim`，`obsidian-handwriting`→`obsidian`。dwm/Xorg 会话已于 2026-11-05 移除。

## 2026-10

| 日期 | 内容 | 原文件 |
|---|---|---|
| 2026-10 | 全面重构计划与软件取舍 | `refactor-plan.md` |
| 2026-10 | v2 架构规范取代的旧版全文 | `architecture-design-v1.md` |
| 2026-10-18 | Den 迁移各批实施与检查 | `den-execution.md` |
| 2026-10-18 | Neovim 重构方案 | `neovim-migration-plan.md` |
| 2026-10-18 | 桌面与窗口优化 | `desktop-polish-execution.md` |
| 2026-10-18 | 系统与编辑器优化、首次自主应用 | `system-polish-execution.md` |
| 2026-10-18 | 面板、场景与 Rime | `panel-rime-execution.md` |
| 2026-10-18–19 | CLI、媒体与桌面 | `system-experience-execution.md` |
| 2026-10-19 | 移除 Hyprland | `hyprland-removal-execution.md` |
| 2026-10-19 | 目录归属与会话边界整理 | `repository-organization.md` |
| 2026-10-19–20 | 历次对话交接 | `execution-handoff.md` |
| 2026-10-20 | 可读性、面板分组与项目布局 | `optimization-2026-10-20.md` |
| 2026-10-20 | 配置审核与 DSH 接线 | `repository-audit-2026-10-20.md` |
| 2026-10-23 | 提交已应用改动、归档分支与文档 | `repository-cleanup-2026-10-23.md` |
| 2026-10-24 | 五轮仓库与系统优化：依赖、启动、桌面、内核、登录与头像 | `optimization-2026-10-24.md` |
| 2026-10-24 | 第六轮 Neovim 完全重构、构建验证与此前历史 | `neovim-rebuild-2026-10-24.md` |
| 2026-10-24 | 第七轮输入法语法模型、候选框主题与 CLI 配色 | `im-cli-polish-2026-10-24.md` |
| 2026-10-24 | 第九轮 Noctalia/Mango 标题条、视觉刻度与动效 | `desktop-polish-2026-10-24.md` |
| 2026-10-24 | 第十轮软件替换、Neovim 启动页与 Lua LSP 实测 | `software-swap-2026-10-24.md` |
| 2026-10-24 | 第八轮 v2.1 重构、B0 对照、逐文件清单与验证边界 | `architecture-v2-execution.md` |
| 2026-10-24 | CLI 视觉与配色 | `visual-cli-2026-10-24.md` |
| 2026-10-24 | Mango/Noctalia 桌面视觉 | `visual-desktop-2026-10-24.md` |
| 2026-10-24 | GTK/Qt、输入法与应用视觉 | `visual-apps-2026-10-24.md` |
| 2026-10-24 | Neovim AI 与原生能力集成 | `nvim-ai-2026-10-24.md` |
| 2026-10-25 | 视觉与 Neovim 收尾集成、性能和完整验证 | `finalize-2026-10-25.md` |
| 2026-10-25 | 第十八轮紧凑界面与下划指示 v3 | `ui-v3-2026-10-25.md` |
| 2026-10-25 | 第二十轮 Neovim 视觉对齐与启动页 | `nvim-visual-2026-10-25.md` |
| 2026-10-25 | 第二十一轮 A：桌面细节与窗口规则 | `ui-r21a-2026-10-25.md` |
| 2026-10-25 | 第二十一轮 B：GTK/Qt 与图标主题 | `ui-r21b-2026-10-25.md` |
| 2026-10-25 | 可选 dwm/Xorg 桌面（r24 前） | `xorg-before-r24-2026-10-25.md` |
| 2026-10-25 | 第二十四轮 dwm/Xorg 重写与视觉验收 | `xorg-r24-2026-10-25.md` |
| 2026-10-25 | Neovim R25 极简专注 | `nvim-minimal-2026-10-25.md` |
| 2026-10-25 | Neovim 全面改造 | `nvim-overhaul-2026-10-25.md` |
| 2026-10-25 | 第二十六轮应用、文件管理与主题 | `apps-r26-2026-10-25.md` |
| 2026-10-25 | Neovim 第二十八轮深度精修 | `nvim-r28-2026-10-25.md` |
| 2026-10-25 | Neovim r28b：DAP 与 which-key | `nvim-r28b-2026-10-25.md` |
| 2026-10-25 | Neovim r29：统一界面与普通输入补全 | `nvim-r29-2026-10-25.md` |
| 2026-10-25 | Neovim r30：原生补全交互与浮窗 | `nvim-r30-native-completion-2026-10-25.md` |
| 2026-10-25 | 顶栏 r31 一体式 One Dark | `bar-r31-unified-2026-10-25.md` |
| 2026-10-25 | WeChat IBus portal 修复 | `wechat-ime-2026-10-25.md` |
| 2026-10-25 | 第十九轮终端套件、科技版系统界面、herdr 与壁纸回退 | `ui-v4-2026-10-25.md` |
| 2026-10-26 | 全桌面整理、flake 更新与迁移 | `desktop-polish-r32.md` |
| 2026-10-26 | Thunar 紧凑样式与 SYSTEM/通知避让 | `desktop-polish-r33.md` |
| 2026-10-26 | 自主视觉巡检、中文菜单、实色浮层与应用证据 | `desktop-polish-r34.md` |
| 2026-10-30–31 | TUI 统一搜索、工具箱、删除无用工具 | `tui-r55-2026-10-31.md` |
| 2026-10-31 | 从顶层文档移出的过时状态原文 | `docs-status-cleanup-2026-10-31.md` |

## 2026-11

| 日期 | 内容 | 原文件 |
|---|---|---|
| 2026-11-03 | Neovim 接入 probe-rs DAP，STM32H562 实机调试 | `nvim-probe-rs-2026-11-03.md` |
| 2026-11-05 | 移除 dwm/Xorg 与 X11 专属组件；QQ Wayland 共享试验撤销 | `xorg-removal-2026-11-05.md` |
| 2026-11-05 | 删除 Codex 工作流、修正过时文档、包源码排除 Markdown、家目录清理 | `cleanup-2026-11-05.md` |
| 2026-11-05 | Neovim 按五个领域重写、审查与“一块画布”视觉 | `nvim-rewrite-2026-11-05.md` |
| 2026-11-06 | 软件清理（删 Codex 与 `codex-acp`、p7zip 换官方 7-Zip、xclip 移出 PATH）、防火墙改 nftables（libvirt 随之切换）、nix-daemon 改 `idle` 调度；Clash TUN VM 测试在 nftables 下通过；构建验证，未应用 | `af05492` |
| 2026-11-06 | 文档版本漂移修正、`service-policy` Docker 描述矛盾修正、`editing-composition` 跟进 clangd `base_cmd`、执行记录合并为本索引并打标签 `history-archive-2026-11-06` | `85a0ef2` |
| 2026-11-06 | 应用 `85a0ef2` 并重启：运行系统与 HEAD toplevel 一致、无失败单元；实机核对 codex 已移除、`7zz` 在 PATH、xclip 不在 PATH、nftables active、nix-daemon idle/idle、独显 suspended。用户实测 Clash TUN 与 libvirt NAT 虚拟机正常（libvirt 在首次启动时由 `libvirtd-config` 写入 nftables 后端） | 实机 |
| 2026-11-06 | MC 中转：Lighthouse（Debian）部署静态 frps 0.66.0（`pkgsStatic.frp`，TLS 强制、只放行 25565、令牌经 `LoadCredential`），nftables 放行 7000/25565 并启用开机加载；笔记本新增 `game-tunnel` feature（按需 frpc 用户服务，令牌为 sops `frp-token`）。Clash baseline 加 `route-exclude-address` 与 fake-ip 过滤让中转直连。端到端测试卡在腾讯云控制台防火墙（7000/25565/22000 均被拦，仅 22 通） | 构建 + 服务器实机；端到端未通 |
| 2026-11-06 | 用户在腾讯云控制台放行 TCP 7000/25565（22000 按用户决定不放行）。端到端实测：frpc 登录成功，公网 `mayonlos.cloud:25565` 经 frps 到本机 127.0.0.1:25565 测试服务，60 ms 收到回包；笔记本到服务器 RTT 约 18 ms。笔记本侧配置尚未应用（需 `nr` 生成 `/run/secrets/frp-token`） | 实机（临时令牌文件） |
| 2026-11-06 | 用户决定改用樱花内网穿透，撤销自建中转：删除 `game-tunnel` feature 与 sops `frp-token`；服务器停用并删除 frps（服务、二进制、`/etc/frp`），nftables 恢复为只开 22/22000（保留开机加载）。笔记本 Clash baseline 的服务器直连例外保留 | 实机 |
| 2026-11-09 | 新增 `chrome` feature：stable `google-chrome` 156 + `--wayland-text-input-version=3`；一次性写入 profile（深色灰阶、竖排标签）与 Local State（关闭后台运行、Memory Saver）；Mango 浏览器规则加入 `google-chrome`。私有无头 sway 中实测：推荐策略会显示“由组织管理”且 `BrowserThemeColor` 推荐级无效，GTK 主题模式渲染为浅色，均未采用 | 构建 + 隔离运行 |
| 2026-11-15 | 用户决定移除 Claude Code 与 Google Chrome：配置不再安装 `claude`、`claude-agent-acp` 与 `google-chrome`，Neovim 不再提供 Claude 面板；本机 Claude 与 Chrome 数据目录已删除 | 配置 |
| 2026-11-15 | 安装 Google Antigravity：`antigravity` 2.32.1 与 `agy` 1.5.9，来自 llm-agents。`nix flake update` 后 Noctalia shell 仍停在 `e439042`（本地补丁打不上 `3e17932`），mark-shot 仍停在 `9dcc564`（上游 main 已没有 `flake.nix`）。系统切换到 `26.05.20261113.f1e5c35` | 应用 |
| 2026-11-15 | 删除 wayscrollshot。把 mark-shot Rust `main` `4cf89101` 放进 `packages/mark-shot`，用 nixpkgs-unstable 的 rustc 1.99.1 构建出 `mark-shot-0.2.0`。窗口矩形改为程序内查询 `mmsg`，`Shift+Print` 改为 `mark-shot --scroll`。运行系统仍是 `26.05.20261113.f1e5c35` | 构建 |
| 2026-11-15 | 登录屏从 Noctalia Greeter 换成 gtkgreet 0.8。外层用 sway 把 `eDP-1` 设为 1.5，因为 cage 0.3.0 不能按输出设缩放。登录命令是不超过 127 字节的 `mango-login`。72px 时钟、中文日期和头像留在锁屏。去掉 flake 输入 `noctalia-greeter`。运行系统仍是 `26.05.20261113.f1e5c35` | 构建 |
| 2026-11-15 | 顶栏改为 mangobar，搜索改为 fuzzel，通知改为 mako，音量/亮度 OSD 改为 swayosd。剪贴板历史改为 cliphist + wl-clip-persist，X11 桥保留。Noctalia 的 bar、通知 daemon、OSD 和 clipboard 关闭，Dock、锁屏和 Launchpad 保留。mangobar 只有一种字体，活动工作区用蓝色数字。运行系统仍是 `26.05.20261113.f1e5c35` | 构建 |
| 2026-11-15 | 重做 Mango 窗口和动画：2 px 描边，单窗口与 monocle 贴边，多窗口间距 10/16，开合 zoom 0.92，工作区横向滑入 280 ms，焦点 120 ms 过渡描边和 dim。运行系统仍是 `26.05.20261113.f1e5c35` | 构建 |
| 2026-11-15 | 修 system-28 激活后的失败项：swayosd 配置去掉 0.3.1 不识别的 `duration`；mako 包不再安装命名不符的 D-Bus 文件，改由 HM 写入 `org.freedesktop.Notifications.service` 并带 `SystemdService=mako.service`。mangobar 样式改成显式清除默认 pill/radius 的平铺布局，活动工作区仍是蓝色数字；fuzzel 间距/行数微调。实机（不切换 generation）验证：swayosd-server 不再 panic，顶栏样式通过环境覆盖渲染成功 | 构建 + 实机片段 |
| 2026-11-15 | mark-shot 0.2.0 修分数缩放覆盖层：Mango 给的 layer configure 尺寸 1706×1066×1.5 = 2559×1599，而截图帧按 1707×1067 取整为 2561×1601，旧代码直接报 “the native frame does not match the configured buffer”，`Print` 框选完全打不开。覆盖层现在按交付字节数反推真实像素网格并重配 shm 缓冲，viewport destination 保持逻辑尺寸。真实会话里框选覆盖层已能正常显示 | 实机 |
| 2026-11-15 | 登录屏：gtkgreet 单会话时隐藏命令选择器（补丁打在被锁定的 gtkgreet 0.8 上），不再把 `/nix/store/...-mango-login` 显示在登录卡里；登录卡/输入框/按钮样式加圆角和蓝色主按钮。Launchpad 插件重写：拆出 `page.luau`/`layout.luau`，响应式 4–7 列、胶囊搜索框、分类 chip、分页胶囊、空状态分区，交互与 IPC 语义保持不变 | 构建 + 静态检查 |
| 2026-11-15 | mangobar 托盘右键 DBusMenu 接入 One Dark：`style.css` 补 `menu`/`menuitem`/`menuitem:hover`/`menuitem:disabled`，给 `pkgs.local.mangobar` 打 `menuitem-disabled.patch`（上游禁用项写死 50% 灰），新增 `mangobar-tray-pixels` 渲染检查：私有无头 sway + 两个真实 SNI/DBusMenu 服务 + wlr virtual pointer 注入右键，断言菜单矩形/12px 圆角/表面/边框/文字/hover/禁用像素，旧样式同检查会失败。并把 `custom/bluetooth` 轮询从 `bluetoothctl`（系统总线不可达时 SIGABRT + coredump）换成一次 `busctl` 读 `org.bluez`；新旧对照实测 60s：旧式 3 次调用新增 6 条 coredump 记录，新轮询 12 次/60s、0 条 coredump，三个图标分支用私有 mock `org.bluez` 验证通过。同一私有 headless Mango+条纹壁纸下顶栏边缘行与壁纸逐像素一致（无底色/无模糊），mako 通知 360×74 逻辑像素、surface 底、brightFg 文字、`on-notify` 的 `pw-play` 由 strace 确认执行（隔离会话无音频 daemon，退出码 1）；swayosd-server 0.3.1 在私有会话不注册 D-Bus 名，OSD 截图未取得 | 构建 + 隔离渲染/实机片段 |
| 2026-11-15 | 按用户要求把 Noctalia 从 main 完全移除（旧状态保留在 `origin/old` 指向的 `1c716d6`）。删除 flake 输入、`local.noctalia`、`mango-session/noctalia.nix` 与 `noctalia/` 补丁/Lua 插件/本地插件/资源检查（含 Launchpad、desktop-menus、legion-conservation widget、锁屏、Dock、控制中心、通知/OSD/壁纸选择器、bar、reconcile sidecar）、`packages/noctalia-clash-status`、`session-support` 的模板 bundle/运行时检查、Firefox/Zathura/Obsidian 的模板 hook、Thunar“设为壁纸”动作和 composition/README 引用。锁屏由 `session-lock`（先暂停播放再 swaylock）统一入口；替代：GTK3/GTK4 改由 HM 静态渲染 `gtk-3.0/gtk.css`/`gtk-4.0/gtk.css`；Qt palette 文件更名 `one-dark.conf`；壁纸改 `swaybg` 静态渲染 + HM 管理的工厂默认图；锁屏/idle 改独立 `swaylock`/`swayidle`（host 增加 `security.pam.services.swaylock`）；polkit agent 改为会话内 `polkit-gnome-authentication-agent-1`；麦克风静音键改 `swayosd-client --input-volume mute-toggle`；Zathura 颜色文件更名 `one-dark`，Obsidian snippet 改名 `nix-dotfiles-one-dark` 并由 HM activation 写入。保留 mangobar/mako/swayosd/fuzzel/cliphist/wl-clip-persist/截图/OCR。功能缺口：无 Dock、Launchpad、控制中心、通知历史/DND、caffeine、会话菜单、壁纸选择器、锁屏日历/头像、自动关屏，以及原 Noctalia hooks 提供的低电量自动挂起与 PPD performance/power-saver 自动切换（脚本可用但不再自动调用）。验证：`nix eval` toplevel、`nix flake check --no-build` 与 toplevel 构建通过（未应用、未实机验证锁屏/壁纸）。`flake.lock` 仍含未引用的 noctalia 节点，需由 lead 运行 `nix flake lock` 清理 | 构建 |

| 2026-11-15 | 应用 system-34：main 上移除 Noctalia（壁纸改 swaybg 静态、锁屏/idle 改 swaylock/swayidle、polkit 会话 agent 修到 libexec）、Super+V 改自写 `mayon-clipboard`、Super+A 改自写纯文字 `mayon-launcher`、mangobar 顶栏全透明且窗口标题居中、mako 通知音、tray DBusMenu One Dark、mark-shot 物理像素网格与剪贴板整包传输修复、mark-shot LGPL 媒体库（OpenH264 录制/GIF 真实跑通）、gtkgreet 单会话隐藏命令下拉。应用后逐项核对：用户服务无 failed，mark-shot 复制剪贴板为 2560×1600 完整 PNG，剪贴板/启动器覆盖层实机截图正常，空格子工作区壁纸+透明顶栏正常；E2E 最终最佳一轮 33 PASS / 1 FAIL / 4 SKIP（剩余为 live 会话干扰造成的 OSD 偶发检测、需重新登录的 session env、新启动器 Noctalia 旧项和 tray 指针注入） | 实机（system-34） |
| 2026-11-15 | 真实运行 E2E 套件落地（`tests/runtime/`）：live 会话 + 私有 headless 环境，真实调用 grim/notify-send/swayosd-client/wl-copy/mark-shot/gtkgreet 并做像素/文件断言；应用后 28 PASS / 1 FAIL（音量 OSD 检测受自动化环境影响，手动截图已验证）/ 7 SKIP（新启动器交互、tray 指针、旧 Noctalia 项、重新登录后的 session env）。 | 实机 + 私有渲染 |
| 2026-11-16 | 撤销 Noctalia 回退。启动器只留 fuzzel（`Alt+Space`），`Super+A` 不再绑定。剪贴板继续用已有的 cliphist，`Super+V` 用 fuzzel 列出历史后 `cliphist decode \| wl-copy` 写回；自写 `mayon-clipboard` / `mayon-launcher` 不进入会话。应用 `/nix/store/m6j85vhhry3l4911n5vwny2phlia1p86-nixos-system-nixos-btw-26.05.20261113.f1e5c35`。首次激活被已有的 `gtk.css.backup` 挡住，两份 2026-06-28 的备份改名保留后再次切换成功。Noctalia 已退出，壁纸为 swaybg，`reload_config` 成功 | 应用 |
## 被取代的规范全文

| 日期 | 内容 | 原文件 |
|---|---|---|
| 归档 | 旧视觉规范全文（含被取代的分层参数） | `visual-design-2026-10-30.md` |
| 归档 | 旧桌面说明全文 | `desktop-design-2026-10-30.md` |
| 归档 | 旧操作方式说明全文 | `workflow-design-2026-10-30.md` |

附带数据（同在归档标签中）：`architecture-v2-{baseline,result}.json`、`architecture-v2-files.tsv` 属于 architecture-v2-execution；`software-swap-dashboard.txt` 与 `software-swap-2026-10-24-data/` 属于 software-swap-2026-10-24。
