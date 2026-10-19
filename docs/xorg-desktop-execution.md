# 可选 dwm / Xorg 桌面

2026-10-19。用户主要需要 QQ、腾讯会议的屏幕共享，明确选择 dwm + Picom，要求参考社区重新配置。
Mango + Noctalia 继续作为默认会话；Xorg 是登录界面的另一个明确选择，不自动叠加运行。
基线为 `62cb424`，开始时工作树干净。保留用户数据、登录状态、剪贴板历史及正在运行的任务。

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
- [Picom v13](https://github.com/yshui/picom/blob/v13/man/picom.1.adoc)：现代 rules 与原生短动画，不引入旧动画 fork。
- [Rofi 2.0 主题](https://github.com/davatorium/rofi/blob/2.0.0/doc/rofi-theme.5.markdown)及[社区设计](https://github.com/adi1090x/rofi)：搜索、结果和模式区的层次。
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

实际 Astra 负责 OneDark 的 Picom/Rofi/Dunst 及原生栏设计；dwm 功能实现由 Luna 完成，
主代理接线与构建，独立 reviewer 检查跨会话边界。配色继续 `#1f2329`、蓝色焦点、清楚的
正文和实底通知。只给浮窗层次阴影，短开关动画，不给平铺移动或共享画面持续模糊。
144 DPI 来自主机 facts；X11 没有 Wayland 那样的逐输出分数缩放，混合 DPI 外屏需单独验收。

原生栏默认音量、电池、时钟，每八秒检查、内容变化才重绘；不常驻轮询 CPU、内存、SSID/IP。
`status2d` 提供图标、分隔线及有限颜色：低电量红、充电绿；选中标签蓝底，标题保持深色。
点击状态区或快捷键打开 Rofi 控制菜单，包含音量、网络、蓝牙、剪贴板、帮助、锁屏和退出。
菜单另有受会话约束的 Picom 开关，退出有二次确认。壁纸与 greeter 共用仓库内 wallpaper-009。

选型比较后采用增强原生栏：它直接掌握 dwm 的 tags、布局和焦点；Polybar 丰富模块需要
另接 EWMH/IPC，Eww 适合更复杂的自制面板。Rofi 按需启动，覆盖应用、窗口和菜单；
dmenu 更简洁，但同等图标/应用入口需要额外接线。没有为此常驻启动器 daemon。
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
锁屏和休眠需实机确认 PAM、屏幕覆盖与唤醒行为。没有在当前工作会话运行锁屏测试。

## QQ / 腾讯会议

QQ 原来的强制 Wayland 参数只在 Mango 保留；真实 Xorg 使用 `--ozone-platform=x11`，
PipeWire 动态库补充继续保留。旧注释中的 QQ 3.2.32 Mango 共享失败记录仍是有日期的历史证据，
不能由本次构建推断 Xorg 已共享成功。

添加锁定 stable 的 `wemeet`。其当前包配方只在 Wayland 会话启用共享 hook；在 Xorg 启动普通
`wemeet`，不使用始终注入该 hook 的 `wemeet-xwayland`。登录状态和会议数据不迁移、不清除。
进入 Xorg 前先正常退出旧会话中的 QQ / 腾讯会议，再从新桌面启动；单实例机制可能复用
旧后端进程，仅新开一个启动命令不等于已切换后端。本次不主动终止正在运行的应用。

实际登录 Xorg 后，分别验证 QQ、腾讯会议：整屏/指定窗口、窗口最小化与恢复、音视频同步、
切换标签时的共享范围、托盘恢复、麦克风/扬声器和结束共享后的恢复。必须以另一端看到的
画面为证据；出现选择器或本地预览不等于共享成功。

## 验证与应用状态

实现、文档与最终构建已完成，主代理实际执行并通过：

- `xorg-session-runtime`：生产 noninteractive Bash 下十项 supervisor 测试、QQ 后端/argv 检查，真实 dwm 的平铺、居中、浮动状态/尺寸恢复、全屏几何恢复、pager 与 Rofi 跨标签切窗；真实十项控制菜单的图标/主题渲染与 Escape 取消，Dunst 通知及 Picom XRender smoke。
- Mango/Noctalia parser、desktop-composition、system-boundaries、treefmt、完整 `nixos-btw` toplevel 构建。
- 最终系统：`/nix/store/2qjcsga4cmm558bxzlclh50ihkrjgqrz-nixos-system-nixos-btw-26.05.20261012.7993f34`。
- 隔离检查：`/nix/store/s9hy07lrawgfpqd2rq09ipihg53mxikf-xorg-session-runtime`；截图、日志与几何结果保存在该输出。日志 `/tmp/codex-xorg-verified-build.log`。未修改输入锁。

Rofi 2.0.0 在测试专用的带图标 `-auto-select` 快速退出路径出现 SIGSEGV；关闭图标的 A/B
通过。源码支持异步图标与退出清理竞态的推测，但没有 backtrace，不能宣称确认具体根因。
生产配置不启用 auto-select；检查改为真实显示窗口选择器后按 Return，保留图标，已通过。
这不是升级无关输入或隐藏生产失败。菜单动作本身、真实系统声音/亮度与退出未在隔离测试中执行。

Astra 在独立 Xvfb 实际运行 i3lock-color 并目检截图，同时用继承的 pipe 确认映射窗口后释放
睡眠延迟 FD。没有输入真实密码，不把该证据写成实机 PAM 解锁成功。

当前仍运行基线 Mango；尚未执行 switch、注销或重启。后续应用范围在本节补记。
真实 Xorg 登录、GLX 显卡路径、共享通话、真实托盘、触控板、多屏热插拔、锁屏/休眠及与
Mango 的能耗比较尚未验证。不把 Xvfb / 求值 / 构建写成实机验收。
