# DWM 视觉与窗口规则

2026-10-19。以 `f4686d6` 干净工作树为本轮基线。用户指出 B 初版视觉和窗口规则不完善，
要求参考社区并由实际 Astra 设计。保留 One Dark 和已选择的
dwm 原生栏、dmenu/j4、Picom、Dunst、i3lock-color 组合。

## 设计与来源

实际 Astra 查看社区原始截图、本仓壁纸以及现有实现后确定：用留白和细线建立层次，
蓝色用于焦点，正文保持不透明；数值 tag 保留原有键位关系。参考
[chadwm 源码](https://github.com/siduck/chadwm/blob/main/chadwm/config.def.h)、
[原始整桌截图](https://github.com/siduck/chadwm/blob/screenshots/screenshots/initial_look.png) 与
[phyOS-dwm 截图](https://github.com/FT-Labs/phyOS-dwm/blob/screenshots/screenshots/s6.png)。
借鉴构图、细边框和浮窗层次，不复制硬件、启动脚本或软件选择。

| 元素 | 当前实现，尺寸为 96 DPI 逻辑值 |
| --- | --- |
| 原生栏 | 高 28，上间距 10、侧间距 14；9.5 字号；活动 tag 蓝字、2 像素下划线 |
| 窗口 | 边框 1，非焦点 surface、焦点蓝；内间距 10、外间距 14；主区 0.60 |
| 启动器与控制菜单 | 居中卡片宽 460，行高 32、四边内距 12、细边框；至多八行结果 |
| 通知 | 宽 320、内距 14/16、圆角 6；普通边框 selection，紧急才红色 |
| 合成 | 浮窗圆角 6、阴影 0.18；平铺、全屏与 dock 无阴影，无模糊和动画 |
| 场景 | Xorg 桌面与锁屏统一公开 wallpaper-005；锁屏预先暗化 28%，时钟 56 |

本机 144 DPI：栏高 42、窗口外间距 21、窗口边框 2；菜单外宽 690、行高 48。
dwm、菜单与 Picom 由 host facts 换算物理像素；Dunst 与锁屏按其 Xft 规则缩放。
状态栏仍每八秒检查、内容变化才绘制，没有增加常驻硬件轮询。

dmenu 5.4 本地补丁在 `aspects/desktop/xorg-session/dmenu/`，通过 Nix override 构建。
按官方 [center](https://tools.suckless.org/dmenu/patches/center/)、
[line-height](https://tools.suckless.org/dmenu/patches/line-height/)、
[border](https://tools.suckless.org/dmenu/patches/border/) 与
[padding](https://tools.suckless.org/dmenu/patches/dmenupadding/) 的实现思路适配锁定版本；
不是把旧版本补丁直接叠加。保留原生焦点屏幕选择、分页及 `-w windowid` 嵌入接口；
新增 `-z` 宽度、`-h` 最小行高、`-bw` 边框、`-ip` 内距与 `-bc` 边框色。
小屏会限制宽度并减少可见候选行，最后一项仍可通过键盘选中。

## 窗口行为

- 普通主窗口平铺，不为 QQ、腾讯会议或 IDE 的整个 class 设置强制浮动。
- DIALOG、UTILITY、SPLASH 居中浮动；有受管理父窗口的 transient 对话框跟随父窗口中心。
- 音量、输入法、Qt 设置、帮助与两个暂存窗口初始为工作区的 65% × 70%；
  网络与蓝牙工具为 60% × 65%。这是初始规则，之后可手动调整大小。
- 单窗口也保留外间距。锁定 vanitygaps 中 `smartgaps_fact=0` 会将单窗口外距清零，
  已改为 1。
- 启用锁定源码的 FLOATPOS，尺寸按工作区计算；浮动切回、全屏返回均检查完整位置与尺寸。
  不能把 `-1C` 当成屏幕居中：它表示保留已有窗口中心。
  当前使用该版本原生支持的 `50% 50%` 工作区中点定位。
- Picom 根据 dwm 写入的 `_MAYON_DWM_FLOATING` 区分平铺/浮动；菜单另有精确 class 规则，
  dock、desktop、通知与全屏保持排除策略。

实现只使用固定 dwm-flexipatch `4c963b33681b277a0ff4d3bf39a27b2feab68950`。
没有更换输入版本、引入独立面板或常驻启动器。

## 证据与应用边界

本轮只读观察：用户当前已在 generation 395 的真实 DWM/X11 会话，
`xorg-session.target` active，`mango-session.target` inactive。运行系统为
`/nix/store/r8ly0x2p8qdbqxxjm14glpd90zw39b11-nixos-system-nixos-btw-26.05.20261012.7993f34`。
这证明此前登录修正已在本次运行中可用，不表示本轮视觉改动已应用。

当前实际窗口清单只有 Kitty，`WM_CLASS="kitty", "kitty"`，浮动标记为 0。
QQ、会议与 IDE 的规则检查使用合成 X11 客户端，不冒充真实应用运行证据；
它们后续出现特殊工具窗口时，应读取实际 class/type/transient，再补精确规则。
不通过猜中文标题把整类程序改成浮动。

设计与构建阶段仅在自有 Xvfb 中运行检查，当时不执行 switch、boot、注销、重启或真实锁屏，
不终止现有任务；用户数据、凭据、历史和模型不变。

## 本轮验证结果

- `xorg-session-runtime` 构建通过：十项 supervisor 生命周期检查、QQ 后端与 argv、
  生产 dwm 的单/双窗口布局、比例浮窗、完整浮动/全屏几何恢复、父子窗口、Qt 工具规则、
  pager 跨 tag 激活。QQ/会议/IDE 主窗口规则为明确的合成 class fixture。
- 生产 j4/dmenu 中文入口与 Exec 参数保真、控制菜单 Escape、未知输入不执行通过。
  第二个 420×260 / 144 DPI Xvfb 验证菜单边界、居中、滚动到末项与取消退出。
  此固定场景不是完整多屏或多 DPI 验收。
- Picom 配置在测试专用 XRender 后端启动，Dunst 实际发送通知，日志无错误。
  生产 GLX 和 NVIDIA/Intel 驱动行为没有借此冒充完成。
- 实际 Astra 逐张查看整桌、启动器、小屏菜单；另建 1600×1000 / 144 DPI Xvfb 运行
  生产锁屏 wrapper，检查时钟、中文、日期与认证环。映射窗口后模拟睡眠延迟 FD 释放通过；
  未输入密码，不证明实机 PAM 解锁或休眠恢复。
- 独立 reviewer 对配方、窗口状态、FLOATPOS 语义、菜单几何、测试边界与服务归属复核。
  构建过程中先后捕获了错误的 floatpos 居中写法及 dmenu 参数解析的宏重复求值，
  均修正后才取得下列最终通过结果；失败迭代不作为通过证据。
- `nix flake check --no-build --no-write-lock-file` 全部求值通过；treefmt、
  `desktop-composition`、完整主机 toplevel 构建通过。输入锁未修改。

窗口实测：1600×1000 显示中，单平铺窗口 x=21、y=78、客户区 1554×897；
Pavucontrol class fixture x=280、y=198、客户区 1036×656；边框计入后按工作区居中。
这些尺寸是隔离输出的测量，不是实际 Pavucontrol 的内容最小尺寸验收。

最终系统：`/nix/store/3y8abkr7hkq0x6gshvaisxh7nan1w6hj-nixos-system-nixos-btw-26.05.20261012.7993f34`。
运行检查：`/nix/store/jwymwzbpm8v8lhlp42krsy5b58cb09p8-xorg-session-runtime`，含四张预览、
`geometry.json`、小屏结果及各进程日志。锁屏预览 `/tmp/dwm-lock-preview-lormuwh7/lock-preview.png`，
仅为临时验收产物，不纳入配置或用户数据。构建日志为 `/tmp/codex-dwm-v2-runtime.log`、
`/tmp/codex-dwm-v2-system.log`。

实现本地提交 `e456740`（视觉与窗口规则）、`0a044d4`（菜单与行为检查）；本轮不 push。
应用新结果后需要重新进入 DWM 才会启动新的 dwm 二进制；本轮没有更换当前运行的 WM。

## 用户授权后的系统应用

2026-10-19 12:41:46，用户明确要求“切换好”。先执行已构建结果的 `dry-activate`，
计划只重启 `home-manager-mayon.service`，不会重启 greetd 或结束桌面；随后执行
`sudo nixos-rebuild switch --flake .#nixos-btw --no-write-lock-file --max-jobs 1 --cores 2`，返回 0。
系统 profile 为 generation 396，`/run/current-system` 指向上述最终系统；
上一代 generation 395 保留。应用日志 `/tmp/codex-dwm-v2-switch.log`。

实际检查：Xorg target、Picom、Dunst、状态、壁纸与空闲锁屏服务 active，Mango target inactive；
用户管理器没有 failed units。Picom 在生产 GLX 配置下启动且没有新增错误日志，
不把短时服务启动扩大为完整 GPU/性能验收。Dunst 重载时尝试 Wayland 后出现警告并回退 X11，
服务仍 active/running、Result=success，`dunstctl` 查询正常；此记录不宣称生产日志完全无警告。

切换前后 greetd 的两个进程、DWM 与两个 Codex 的 PID/启动时间均未改变，没有注销或重启。
现有 DWM PID 2373 仍运行旧包 `ccdpq46w06gpwd46whkalsgjc8n9c42c`；已激活的会话脚本指向
新包 `jb17b1bkgjrirz9jmc30927i0ql2cdba`。菜单、通知、合成与壁纸配置已加载，
新 DWM 的栏、间距和窗口规则需要用户之后重新登录 **DWM** 才生效；不能标为已热加载。
