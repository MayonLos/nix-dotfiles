---
summary: 可选的 dwm + Picom 真 Xorg 会话：入口、键位对照、服务
read_when: QQ/腾讯会议原生捕获、修改 Xorg 会话
code: [aspects/desktop/xorg-session]
checks: [xorg-session-runtime]
---

# 可选 dwm / Xorg 桌面

登录器默认 **Mango**，可选 **DWM** 进入真正的 Xorg。两会话互斥；用途是 QQ、腾讯会议、OBS 等应用的原生 X11 捕获。

唯一视觉依据为用户确认的 `scratchpad/dwm/design.html` 与 `design.png`；现行实现、参考
取舍、截图迭代和构建结果见[本轮执行记录](history/xorg-r24-2026-10-25.md)。旧选型、登录
修复和应用记录已[归档](history/xorg-before-r24-2026-10-25.md)，不代表本轮实现或应用状态。

## 设计落地

| 设计 | 实现 |
|---|---|
| 30 逻辑 px 浮动圆角栏 | 原生 barmodules，144 DPI 高45px，上/侧9/12px；Picom 圆角15px |
| 标签短下划、占用点、紧急红线 | 本地 tags renderer，保留原生标签点击区域，不使用选中填充胶囊 |
| Tile / Mono / Float、标题、居中时钟 | 时钟首先分配显示器中心，左右分别裁切；标题中性配色 |
| CPU / RAM / 网络 / 音量 / 电池养护 / IME / 通知 | 单一5秒 status producer；只画数值及状态，不显示SSID/IP/主机名 |
| 圆角10、蓝边2、阴影、非焦点dim6% | Picom13 + dwm边框，fade约80ms；reducedMotion关闭fade，游戏/全屏/锁屏豁免 |
| Rofi Apps/Run/Windows/Clipboard | 560逻辑宽、deep底、左蓝条、模式标签下划；彩色原生应用图标 |
| 五格电源菜单 | Lock/Logout/Suspend/Reboot/Shutdown；后四项另一次确认，未知输入不执行 |
| Dunst通知320、左色条与进度 | 1.13 Cairo局部补丁，级别只染左条、正文中性；原生进度hint |
| 同壁纸锁屏 | i3lock-color，暗化缓存只在用户runtime/cache；保留PAM/nofork/睡眠延迟FD |
| 壁纸与指针、字体、输入法 | 共享palette/Bibata-Modern-Ice/Fcitx/xrdb；读同一managed/local目录，默认005 |
| 截图 | Print区域→Satty标注/复制/保存，Ctrl+Print全桌复制；Super Print系列OCR |
| 托盘、外屏、暂存工具 | 原生systray、RandR事件热插拔、终端/Yazi/btop三个scratchpads |

Fcitx原生托盘图标保留引擎自己的中英子模式；status中/英仅表示`fcitx5-remote`整体激活，
不能当作Rime内部ASCII状态。网络图标依据默认IPv4路由，通知数字为Dunst等待队列数。
X11没有Wayland逐输出分数缩放；混合DPI外屏仍需现场验收。

## 键位对照

Super指Win键。完整dwm键位由`dwm/keybindings.json`生成并由Super+F1显示。

| 操作 | Mango | dwm / Xorg |
|---|---|---|
| 终端/浏览器/文件 | Super+Return/B/E | 相同，调用共享workspace wrapper |
| 启动器/剪贴板 | Alt+Space / Super+V | 相同，Rofi Apps / Clipboard |
| 控制菜单/电源 | Super+S / Ctrl+Alt+Delete | 相同，Rofi桌面控制 / 五格电源；另保留Super+P |
| 锁屏/勿扰/防休眠 | Super+Alt+L / Super+Alt+D / Super+Shift+A | 相同修饰键；分别调用锁屏/Dunst/idle-unit |
| 方向聚焦/移窗 | Super+HJKL或方向 / 加Shift | 相同；dwm平铺交换方向邻窗，浮窗按栏高移动 |
| 前后切窗/上次焦点 | Super+Home/End / Super+Tab | 相同 |
| 浮动/最大化/全屏 | Super+Space / Super+F / Super+Shift+F | 相同；最大化保留栏并恢复原几何 |
| 主窗口/主区数量 | Super+Z / Super+Shift+I/U | 相同 |
| 主区比例 | Super+Minus/Equal；Super+Ctrl+R/F | 相同（±5%，55%/90%） |
| 布局 | Super+W循环 | 相同；另有Super+T / Super+M / Super+Shift+T直达Tile/Mono/Float |
| 标签/移到并跟随/只停放 | Super+1–9 / Super+Shift+1–9 / Super+Ctrl+1–9 | 相同 |
| 前后标签 | Super+I/U或Super+PageUp/Down | dwm相邻数字标签；Mango跳占用标签 |
| 移到外屏 | Super+Ctrl+方向 | dwm按Xinerama顺序前后屏；另有Super+Shift+逗号/句号 |
| 跨标签/置顶 | Super+Ctrl+G / Super+Alt+G | 同一修饰键 |
| 暂存终端/Yazi/btop | Super+Shift+Return / Super+Alt+E / Super+Alt+M | 相同 |
| 区域/全桌截图 | Print / Ctrl+Print | 相同目的；X11用slop+maim/Satty |
| 区域/全桌OCR | Super+Print / Super+Shift+Print | 相同修饰键；X11用Tesseract中英识别 |
| 壁纸下一张/屏幕熄灭和唤醒 | Super+Shift+W / Super+Shift+P和Super+Shift+O | 相同修饰键 |
| 音量/麦克风/亮度/媒体 | XF86键 | 相同；Dunst进度通知替代Noctalia OSD |

Mango的滚动截图（裸Shift+Print）、overview、特殊工作区、resize模式和mark-shot贴图没有
逐项伪装成X11功能。Xorg保留相同高频操作，局限与替代如上；不改Mango键位。

## 会话、writer与状态

唯一入口`xorg-dwm.desktop`由host投递，调用HM安装的supervisor；加载HM登录变量时暂时
关闭nounset，保留此前实机故障修复。互斥检查与进程锁先于共享环境写入；dwm发布EWMH
就绪后才启动target。退出只通知记录且已核验的supervisor PID，停止自己的target并恢复
白名单环境，不执行pkill或终止整个登录会话。

Picom/Dunst/CopyQ/polkit/status/壁纸/输出watcher/idle/xss-lock只属于`xorg-session.target`，
都有desktop与target约束；Dunst D-Bus激活也走受约束unit。Noctalia和Wayland/X11 bridge仍
只属Mango。纯Xorg没有Wayland selection域，不启动无对端bridge；CopyQ负责X11历史，
不读取、迁移或清除Noctalia历史。Fcitx/xrdb/PipeWire sockets经共享session-target契约复用。

空闲15分钟锁屏、30分钟熄屏、60分钟休眠，与当前Mango源码一致。xss-lock独立保护显式
睡眠/合盖；防休眠按钮仅暂停自动空闲策略。RandR watcher在连接集合变化时按首选模式排
横向桌面（内屏优先），不保存/覆盖用户显示器profile；dwm随root几何调整重新分布窗口。

配置与生成目标归[feature README](../aspects/desktop/xorg-session/README.md)；托管壁纸目录
仍由Mango唯一声明，Xorg只读。Xorg当前壁纸路径与socket是私有runtime状态，暗化local图
只在cache生成。Qt/GTK/Neovim无改动；应用账号、截图、历史、模型、容器卷与VM镜像保留。

QQ wrapper在Xorg选择`--ozone-platform=x11`，腾讯会议使用普通`wemeet`。进入新会话前
须正常退出旧会话中的单实例应用，再从新桌面启动；构建不能证明它已换后端或完成共享。

## 验证边界

本轮要求的隔离显示为2560×1600、DPI144，私有HOME/XDG/D-Bus，Picom使用XRender。
截图与实际命令结果记录于[第二十四轮记录](history/xorg-r24-2026-10-25.md)。验证不激活系统。
待实机：从greeter真正登录/退出DWM、驱动GLX/外屏热插拔/混合DPI、Fcitx子模式与应用
输入、托盘恢复、PAM解锁/休眠唤醒，以及QQ/腾讯会议/OBS实际原生捕获。
