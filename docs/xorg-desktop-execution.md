# 可选 dwm / Xorg 桌面

2026-10-19。用户主要需要 QQ、腾讯会议的屏幕共享，明确选择 dwm + Picom，要求参考社区重新配置。
Mango + Noctalia 继续作为默认会话；Xorg 是登录界面的另一个明确选择，不自动叠加运行。
基线为 `62cb424`，开始时工作树干净，保留本地分支 `codex/xorg-baseline-20261019`。保留用户数据、登录状态、剪贴板历史及正在运行的任务。

## 首次实机启动与登录修复（上一轮）

2026-10-19 11:48:12，用户选择原显示名 `One Dark Xorg (dwm)`，认证成功；
11:48:13 返回登录器。当前 `/run/current-system` 已是下文 generation 394，不能继续按
“尚未重启”的历史状态判断。`~/.local/share/xorg/Xorg.0.log` 记录 Intel modesetting / NVIDIA
初始化，最后为 `Server terminated successfully (0)`，未出现致命初始化错误。
同目录 `.old` 是 2026-05-03 的旧记录，其中的显卡错误不属于此次启动。

原入口没有把 client stderr 接入 journal，现有日志不能直接证明 supervisor 的具体退出行。
只读隔离复现发现：在最小公开登录环境下，以生产 Bash 的 `-u` 模式加载当前真实
`/etc/profiles/per-user/mayon/etc/profile.d/hm-session-vars.sh`，第 34 行报
`QT_PLUGIN_PATH: unbound variable`，退出 127；同一环境不启用 nounset 则返回 0。
HM 生成的 `QT_PLUGIN_PATH`、`XCURSOR_PATH` 导出语句允许变量此前未定义，supervisor
不应要求这段 POSIX 登录脚本兼容 nounset。这是已复现的启动缺陷，与本次立即退出相符；
原始 client stderr 缺失，仍不能据此宣称已实机确认唯一故障点。

修复只在加载 HM 环境期间关闭 nounset，成功后恢复；加载失败明确报错。回归 fixture
加入这两条真实形式的导出：旧 supervisor 必然失败，修复后十项生命周期检查通过。
登录入口将 client 输出接入 `journalctl -b -t xorg-session`，以便保留后续失败证据；
显示名称改为 **DWM**，内部 desktop ID `xorg-dwm` 保持稳定。
本轮只修改、构建，不 switch、不更新启动默认 generation、不启动或停止现有会话。
组件重设计先形成方案，不把选型讨论当成已经部署。

本轮独立 reviewer 复核 source 边界、日志入口与信号/PID 语义；十项 supervisor 测试、
`xorg-session-runtime`、`desktop-composition`、treefmt 与完整主机系统构建通过。
最终修复系统为 `/nix/store/mqv17pkf0wrx9ng62prvrflvcjgp2zkc-nixos-system-nixos-btw-26.05.20261012.7993f34`，
隔离检查为 `/nix/store/n1mzdhamc10mclhpydhnw081b6v4fw34-xorg-session-runtime`，
构建日志 `/tmp/codex-xorg-login-fix-final.log`。它们尚未应用，不证明真实登录已恢复。

## 组件选择与 B 实现

用户先要求比较，随后明确选择 **B**。实际 Astra 负责 Picom/Dunst/锁屏视觉，Luna 负责
dwm 配置，主代理实现 dmenu 启动器/控制菜单、集成和检查。OneDark 与 Nix 声明式构建继续。
下表保留选型比较；B 已实现，尚未应用到运行系统。

| 方向 | 组合 | 取舍 |
| --- | --- | --- |
| 极简 | 原生栏 + slstatus + dmenu + slock，Picom 可关闭 | 纯文本、少装饰；GUI desktop 入口仍需 helper，锁屏需单独迁移现有认证接线 |
| B 精致简洁（已选择） | 增强原生栏 + 小状态脚本 + dmenu/j4-dmenu-desktop + 轻 Picom + Dunst + i3lock-color | 保留托盘、浮窗层次与中文应用入口，启动器按需；较少组件又可统一美化 |
| 搜索与视觉完整 | 上一组启动器改 Rofi，保留应用图标与跨标签窗口搜索 | 沿用当前已安装组件较多；Rofi 同样按需，不能说换 dmenu 就减少了常驻进程 |

社区参考及边界：

- [siduck/chadwm](https://github.com/siduck/chadwm)：原生栏 + status2d、Rofi、Picom，Eww 是另一可选部件；
  借鉴标签状态、分组与间距。它的栏不是 Polybar，也不是 dwmblocks。仓库安装脚本、
  硬件名和轮询策略不直接复制到本机。
- [LukeSmithxyz/dwm](https://github.com/LukeSmithxyz/dwm) 与
  [dwmblocks](https://github.com/LukeSmithxyz/dwmblocks)：借鉴可点击状态、scratchpad 和键盘操作。
  dwmblocks 是给原生栏提供状态的进程，不是另一套绘制面板；具体工具和 LARBS 键位不照搬。
- [dwm-flexipatch](https://github.com/bakkeby/dwm-flexipatch)：延续当前固定 revision 作为补丁组合基础；
  不为了社区新提交升级本机输入，也不默认启用全部补丁。
- [Polybar xworkspaces](https://github.com/polybar/polybar/wiki/Module:-xworkspaces)：模块丰富，
  但要求对应 EWMH atoms；dwm 多标签语义需额外接线。当前需求优先使用原生栏。
- [j4-dmenu-desktop](https://github.com/enkore/j4-dmenu-desktop)：使用已有 desktop 解析器，
  不自己解析 Exec；[Rofi](https://github.com/davatorium/rofi) 是有图标和窗口搜索的替代选项。

B 视觉方向：`#1f2329` 正文背景、`#181b20` 栏底、`#4fa6ed` 焦点；正文不透明，
顶部窄栏用小色块区分活动标签，音量/电池/时间分组。只给浮窗轻阴影，
不默认全屏模糊或持续动效；Picom 可以随时关闭。启动器和通知采用同一字号、边框与
选中色，保留中文显示。锁屏先精简当前 i3lock-color，而非为了换名重接认证。
窗口规则优先正确区分会话对话框、文件选择、音量设置与普通主窗口；保留可调间距、
逐标签布局、浮动尺寸恢复、全屏恢复与暂存终端。

B 的具体实现：

- 使用 stable dmenu 5.4 与 j4-dmenu-desktop 3.2，不加新补丁或 daemon。`xorg-dmenu` 为统一
  字体/配色入口，`xorg-launcher` 将 desktop Exec/Terminal 解析交给 j4，频次记录保留在
  `$XDG_STATE_HOME/nix-dotfiles/dmenu-usage`（未设置时为 `~/.local/state/...`）。
- 原生栏高度 30、上/侧间距 6/8、窗口内/外间距 6/8、边框 2，均以 96 DPI 为逻辑基准；
  本机 144 DPI 统一转换为 45、9/12、9/12、3 物理像素。主区比例 0.60。
- Picom 无模糊、无变暗、无动画；平铺直角无阴影，仅浮窗使用逻辑 8 圆角和 0.22 阴影。
  全屏、dock 和 Dunst 有明确排除，合成开关继续可用。
- Dunst 中文字体 10.5、逻辑宽度 340、最多三条；圆角 8，正文实底。
- i3lock-color 使用构建时暗化的公开壁纸、时钟 52 和认证环 36，保留 PAM、nofork 和
  xss-lock FD 协议。没有新增屏幕捕获或第三方锁屏管理器。
- Alt+Space 打开应用入口，Super+P 打开九项桌面菜单。控制菜单仅匹配已知文字，
  未知输入不执行；退出仍二次确认。Rofi 的主题、包声明及窗口搜索入口已从 Xorg 方案移除。
  Super+J/K 与标签切窗继续保留，不能将 dmenu 描述为具有 Rofi 的窗口搜索功能。

## 架构与来源

`xorg-session` 是按用户绑定的 Den aspect，复用 `interactive-session` 的字体、GTK/Qt、输入法、
音频与 portal 宿主支持；只有选择该功能的主机才安装 Xorg/startx/PAM 和登录项。
真实选择位于 `inventory/hosts/nixos-btw/default.nix`，不添加虚构主机。

dwm 通过 Nix 包配方固定源码、补丁开关和生成的 C 配置，构建发生在 Nix store，不在家目录
执行 `make install`。不修改 `flake.lock`，其余软件使用现有锁定 stable 包。
锁定 stable 的原始 dwm 是 6.6；所需官方独立补丁的组合存在实际冲突，因此新配方固定
`dwm-flexipatch` 的 6.8 基线提交 `4c963b33681b277a0ff4d3bf39a27b2feab68950`，
hash 为 `sha256-xYspDyPPBqTkO4SrB2+u1mUPTbWI52asXWjU0NFd2AU=`。只开启所需补丁，
生成后的 `config.h`、`patches.h` 与来源说明安装到 dwm 包的 `share/dwm/`，方便审查。
没有启用额外的 NixOS 默认 dwm 登录入口：它会再增加一个绕过本功能 supervisor 的会话。
自定义 `xsessions/xorg-dwm.desktop` 是唯一入口，执行同一个 Nix 构建的 dwm。

参考来源：

- [suckless barpadding](https://dwm.suckless.org/patches/barpadding/)、[systray](https://dwm.suckless.org/patches/systray/)：原生栏的间距、托盘与多屏。
- [vanitygaps](https://dwm.suckless.org/patches/vanitygaps/)、[pertag](https://dwm.suckless.org/patches/pertag/)、[scratchpads](https://dwm.suckless.org/patches/scratchpads/)：可调间距、逐标签布局和暂存窗口。
- [dwm-flexipatch](https://github.com/bakkeby/dwm-flexipatch)：选择性组合补丁的兼容实现，不执行社区安装脚本。
- [Picom v13](https://github.com/yshui/picom/blob/v13/man/picom.1.adoc)：现代 rules，B 不启用动画或旧动画 fork。
- [dmenu](https://tools.suckless.org/dmenu/) 与 [j4](https://github.com/enkore/j4-dmenu-desktop/tree/r3.2)：菜单与 desktop 应用入口。
- [i3lock](https://github.com/i3/i3lock)：配合 xss-lock 的 suspend-delay FD；不是直接从 systemd 睡眠钩子异步启动锁屏。

## 会话与服务

锁定 Noctalia Greeter 会枚举 `xsessions`，为 X11 条目调用 `noctalia-greeter-xsession`，
后者经 startx 启动真正的 Xorg。宿主启用 `services.xserver.enable`、startx，保留现有
Intel modesetting / NVIDIA PRIME offload；没有强制桌面使用独显。Xorg 输出名不照抄 Wayland 的 `eDP-1`。
检查实际生成文件后，移除旧 `videoDrivers` 中重复的 modesetting 声明：当前 PRIME 模块已
根据 Intel BusID 添加它，重复声明会生成重名的 Device/Screen 和两条 ServerLayout Screen。
检查产物时断言 identifier 唯一。自然滚动、轻触点击、clickfinger 与打字防误触对齐 Mango。

HM 安装 `~/.local/share/nix-dotfiles/xorg-session`。该 supervisor 拒绝与已活动的 Mango /
graphical target 重叠，加载公开 HM 环境，设置 X11/Qt/Fcitx 后端，只白名单导入 systemd 和
D-Bus；dwm 就绪后启动 `xorg-session.target`。退出仅向自己的子进程转发信号，清理本会话
target 和环境。控制菜单二次确认退出，通过私有 runtime PID 记录定位本 supervisor，
不使用 `pkill`、`kill 0` 或终止整个 logind 会话。

| 服务 | 归属 |
| --- | --- |
| Picom、Dunst、CopyQ、状态栏、polkit agent、xss-lock、壁纸/屏幕超时 | 仅 `xorg-session.target`，校验当前 desktop 为 dwm |
| Noctalia、Wayland/X11 clipboard bridge | 仅 `mango-session.target` |
| Fcitx、xrdb | 两个已选会话共用；同一时间只运行一个会话 |
| PipeWire / Pulse sockets | 由选中的会话请求，保留 socket activation |

Dunst 的 D-Bus 激活入口指向受 target 约束的 systemd unit，不允许在 Mango 内直接自启抢占
通知名称。CopyQ 历史为应用数据，不托管、不清除；不迁移或覆盖 Noctalia 的历史。
Xorg portal 使用 GTK 文件选择、GNOME Settings 和 keyring；不把 ScreenCast/Screenshot
错误路由到 wlroots/Mutter，Xorg 共享采用应用本身的原生捕获。

## 外观与操作

实际 Astra 负责 OneDark 的 Picom/Dunst/锁屏及原生栏设计；dwm 功能实现由 Luna 完成，
主代理接线与构建，独立 reviewer 检查跨会话边界。配色继续 `#1f2329`、蓝色焦点、清楚的
正文和实底通知。只给浮窗层次阴影，不启用动画或持续模糊。
144 DPI 来自主机 facts；X11 没有 Wayland 那样的逐输出分数缩放，混合 DPI 外屏需单独验收。

原生栏默认音量、电池、时钟，每八秒检查、内容变化才重绘；不常驻轮询 CPU、内存、SSID/IP。
`status2d` 提供图标、分隔线及有限颜色：低电量红、充电绿；选中标签蓝底，标题保持深色。
点击状态区或快捷键打开 dmenu 控制菜单，包含音量、网络、蓝牙、剪贴板、帮助、锁屏和退出。
菜单另有受会话约束的 Picom 开关，退出有二次确认。壁纸与 greeter 共用仓库内 wallpaper-009。

选型比较后采用增强原生栏：它直接掌握 dwm 的 tags、布局和焦点；Polybar 丰富模块需要
另接 EWMH/IPC，Eww 适合更复杂的自制面板。dmenu/j4 按需启动，覆盖应用和菜单；
不提供图标式窗口搜索，没有为此常驻启动器 daemon。
锁屏选 i3lock-color 2.13.c.5，Nix 预先暗化公开壁纸；时钟、日期、键盘布局与认证环统一
配色。蓝色表示验证中，红色失败，绿色按键反馈；认证成功直接解锁，没有虚构成功闪绿。
betterlockscreen 的主要图片缓存功能已由此构建步骤覆盖。

常用键位：Super+Return/B/E 为终端/浏览器/文件管理；Alt+Space 启动器，Super+P 菜单，
Super+F1 帮助。Super+J/K 切窗，H/L 调主区比例，T/M/Shift+T 为平铺/monocle/自由布局，
F 全屏，Shift+Space 浮动，Q 关闭。Ctrl+Return 提升到主区，I/U 增减主区数量；逗号/句号
切屏，加 Shift 移窗。Super+Shift+Return 暂存终端、Super+Alt+E 暂存 Yazi；浮动切回后保留尺寸。
这些操作不声称与 Mango HJKL 方向导航完全一致。

隔离运行还发现固定社区源码的原生 `setfullscreen` 在分支内调整尺寸后，又在函数末尾重复
`resizeclient`，覆盖了返回浮窗所需的旧尺寸。本地配方精确移除该重复调用，并检查源码锚点；
实际 Xvfb 样本验证 640×420 → 1600×1000 → 640×420，不能只凭 EWMH 标记清除判断退出正常。

Xorg 截图采用 maim/slop/xclip：Print 选择区域，Ctrl+Print 截取整个 X 桌面；取消选区不报错。
不在 Xorg 使用 Wayland 的滚动截图/区域选择工具。空闲十分钟触发锁屏，十五分钟 DPMS 关屏；
锁屏沿用现有 PAM / xss-lock 接线；这不是另立的休眠功能开发任务。

## QQ / 腾讯会议

QQ 原来的强制 Wayland 参数只在 Mango 保留；真实 Xorg 使用 `--ozone-platform=x11`，
PipeWire 动态库补充继续保留。旧注释中的 QQ 3.2.32 Mango 共享失败记录仍是有日期的历史证据，
不能由本次构建推断 Xorg 已共享成功。

添加锁定 stable 的 `wemeet`。其当前包配方只在 Wayland 会话启用共享 hook；在 Xorg 启动普通
`wemeet`，不使用始终注入该 hook 的 `wemeet-xwayland`。登录状态和会议数据不迁移、不清除。
进入 Xorg 前先正常退出旧会话中的 QQ / 腾讯会议，再从新桌面启动；单实例机制可能复用
旧后端进程，仅新开一个启动命令不等于已切换后端。本次不主动终止正在运行的应用。

QQ / 腾讯会议共享采用 X11 原生捕获，不新增共享 hook、portal 适配或专项开发任务。
本轮没有实际通话证据，因此不声称已经共享成功；这一区别不构成额外配置要求。

## 验证与应用状态

以下是初版构建历史，B 当前构建记录另列于末尾。主代理当时实际执行并通过：

- `xorg-session-runtime`：生产 noninteractive Bash 下十项 supervisor 测试、QQ 后端/argv 检查，真实 dwm 的平铺、居中、浮动状态/尺寸恢复、全屏几何恢复、pager 与 Rofi 跨标签切窗；真实十项控制菜单的图标/主题渲染与 Escape 取消，Dunst 通知及 Picom XRender smoke。
- Mango/Noctalia parser、desktop-composition、system-boundaries、treefmt、完整 `nixos-btw` toplevel 构建。
- 最终系统：`/nix/store/2qjcsga4cmm558bxzlclh50ihkrjgqrz-nixos-system-nixos-btw-26.05.20261012.7993f34`。
- 隔离检查：`/nix/store/s9hy07lrawgfpqd2rq09ipihg53mxikf-xorg-session-runtime`；截图、日志与几何结果保存在该输出。日志 `/tmp/codex-xorg-verified-build.log`。未修改输入锁。

初版使用的 Rofi 2.0.0 在测试专用的带图标 `-auto-select` 快速退出路径出现 SIGSEGV；关闭图标的 A/B
通过。源码支持异步图标与退出清理竞态的推测，但没有 backtrace，不能宣称确认具体根因。
生产配置不启用 auto-select；检查改为真实显示窗口选择器后按 Return，保留图标，已通过。
这不是升级无关输入或隐藏生产失败。菜单动作本身、真实系统声音/亮度与退出未在隔离测试中执行。

Astra 在独立 Xvfb 实际运行 i3lock-color 并目检截图，同时用继承的 pipe 确认映射窗口后释放
睡眠延迟 FD。没有输入真实密码，不把该证据写成实机 PAM 解锁成功。

以下是首次交付时的历史应用记录，当前故障状态以上文为准。源码提交 `0234407`。已执行 `nixos-rebuild boot`，返回 0，系统 profile 指向上述新系统，
作为下次启动配置（generation 394）；日志 `/tmp/codex-xorg-boot.log`。没有执行 switch、注销或重启，Home Manager
和新的 Xorg 服务尚未在运行系统激活。

首次交付时 `/run/current-system` 仍为基线 `h2m1d2llqhvr4c6xmiw9vkdca4awwx21` 系统，Mango target active；
前后六个受保护 PID/启动时间全部保持，包括 greetd、Mango、两个 Codex 和 Java 任务。
登录包实际包含 Mango、Steam 和唯一的 `xorg-dwm.desktop` X11 条目。

用户随后已重启并报告 Xorg 登录失败，目前回到 Mango。首次构建与 Xvfb 检查未覆盖真实
HM 登录环境中的 nounset 冲突，不能作为实机登录成功的证据。修复尚未应用；应用后登录项
将显示 **DWM**。基线 generation 与本地代码分支均保留，没有执行 GC 或 push。

共享采用 X11 原生能力，休眠沿用系统机制与现有锁屏接线，功耗由组件选择与实际工作负载决定；
这些不另列为本轮额外配置任务。仍不把未做的实机行为写成已通过。


## B 构建检查

B 的 `xorg-session-runtime`、`desktop-composition`、treefmt 与完整主机系统构建已通过。
隔离显示使用主机 144 DPI 与 Xft 设置，实际执行中文 desktop 应用选择/Exec 参数、菜单取消、
未知输入不执行，以及既有浮动/全屏恢复检查。j4 显式使用 Kitty 模式，避免通用临时脚本，
日志限制为 WARNING；未启动真实终端应用。Astra 已查看菜单、浮窗和通知截图。
构建日志 `/tmp/codex-dwm-b-final.log`，系统输出
`/nix/store/pfmkvkqdx40n3yf887mskvbhjnm0dyk0-nixos-system-nixos-btw-26.05.20261012.7993f34`。
本轮不 switch、不更新启动默认项；尚未实机确认 DWM 登录恢复，也没有清除用户状态。
