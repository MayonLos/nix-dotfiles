---
summary: dwm 会话的视觉参数与窗口规则
read_when: 调整 dwm、Picom、Rofi、Dunst 外观
code: [aspects/desktop/xorg-session]
checks: [xorg-session-runtime]
---

# DWM 视觉与窗口规则

设计起点（2026-10-19）：用户指出 B 初版视觉和窗口规则不完善，
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

## 证据

隔离验证、窗口实测与 2026-10-19 的系统应用记录见[历史记录](history/docs-status-cleanup-2026-10-31.md)。dwm 二进制更新后，需要重新登录 **DWM** 才生效，不能热加载。
