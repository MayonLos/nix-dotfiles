---
summary: Mango 桌面的组成、窗口规则、独立会话组件和跨应用外观分工
read_when: 修改顶栏、通知、OSD、壁纸、锁屏、窗口规则或应用主题接线
code: [aspects/desktop/mango-session, aspects/desktop/session-support, aspects/desktop/greeter]
checks: [desktop-composition, mango-blur-sampling, interactive-session-config, greeter-tech, gtk-qt-theme]
---

# Mango 桌面

参数值见 [visual.md](visual.md)，按键见 [keymap.md](keymap.md)，文件归属见 [config-ownership.md](config-ownership.md)。功能细节和补丁清单在 [Mango README](../aspects/desktop/mango-session/README.md)。

## 组成

- **顶栏**：mangobar，高 30，完全透明（无背景、不模糊）。左侧为布局符号、工作区编号，以及最小化窗口数量（`hideclients`，数量为 0 时不画）；中间是窗口标题；右侧托盘、`CPU {usage}%`、`MEM {}%`、网络、电池百分比、中文日期时间。`{usage}` 是 `/proc/stat` 的占用百分比，内存 `{}` 是 `(MemTotal−MemAvailable)/MemTotal`；不用 `{load}`，那是 1 分钟 load average。栏上没有蓝牙状态。整条栏只有一种字体 `Maple Mono NF CN` Medium，活动工作区是蓝色数字，没有下划线。窗口标题来自 Mango 的客户标题，布局是 `layout_symbol`，托盘里的 `en` 是 fcitx。托盘右键 DBusMenu 由 mangobar 自绘，同一份 stylesheet 以 One Dark 着色（surface/border/hover/禁用项），对所有 SNI 程序生效。
- **搜索与启动器**：`Alt+Space` 打开 `fuzzel --no-icons`，这是唯一的启动器，列表不画应用图标。`Super+V` 用 Kitty 浮窗打开 cliphist-tui，在现有 cliphist 历史里预览图片（Kitty 图形协议），回车写回 Wayland 并尝试粘贴。锁定的 Mango 热区默认关闭（`enable_hotarea` 为 0）；打开后进入概览，不是启动器。门户选择器保持 `chooser_type=none`。没有 Dock、控制中心或会话菜单。
- **通知与 OSD**：mako 在右上，宽 360，不透明、无模糊；D-Bus 激活文件由包覆盖改成正确命名并带 `SystemdService=mako.service`，通知早到也只会拉起同一个用户单元。音量和亮度是 swayosd（含麦克风静音的 `--input-volume`），媒体键仍是 playerctl。swayosd 0.3.1 对未知配置键会 panic，配置只写它认识的键。
- **壁纸**：`~/Pictures/Wallpapers/managed` 只读内置，`local/` 归用户。`sweetbgd` 作为会话服务绘制，HM 声明 `~/.config/sweetbg/config.toml`（工厂默认图、背景色、`cover`）；Mango 自己不渲染壁纸。`Super+W` 打开 Matuwall 网格，列出这两处的图片；选中后 `wallpaper-apply` 写 `~/.local/state/mango-session/wallpaper` 并通过 IPC 切图，不重启渲染器。状态无效或缺失时仍画工厂默认图 `wallpaper-005.png`。登录屏和锁屏继续用这张默认图，不读该状态文件。
- **锁屏与 idle**：独立 `swaylock`（Mango 支持 ext-session-lock-v1）+ `swayidle`。没有空闲计时器：不会因为一段时间没操作而锁屏或挂起。`Super+Alt+L` 手动锁屏；logind 发起睡眠（合盖、手动 suspend）前会先锁。PAM 服务在 host 侧声明。不模拟自动关屏。
- **登录**：gtkgreet 0.8，外层 sway 按 host facts 设置内屏缩放，背景用 CSS `cover`。只有 Mango 一个会话，登录卡会隐藏命令选择器，不再显示 `mango-login` 的 store 路径。gtkgreet 自带 `HH:MM` 时钟。细节在 [greeter README](../aspects/desktop/greeter/README.md)。

## 服务

Mango 配置用 `mmsg dispatch reload_config` 重载；Home Manager activation 会在每次 `nixos-rebuild switch` 后自动找到当前 Mango socket 并重载一次，所以新快捷键在切换后立即生效。mangobar、mako、swayosd、sweetbgd、swayidle、cliphist 和 wl-clip-persist 都挂在 `mango-session.target` 上，生命周期见 [service-policy.md](service-policy.md)。锁屏与 idle 没有常驻 shell 进程；swayidle 只执行固定命令。

## 窗口规则

唯一规则表是 `mango/window-rules.nix`，字段以锁定 Mango 的解析器为准。规则按顺序覆盖；`app_id` 与 `title` 同写时是 AND，标题变化后不重新匹配。

- 文件选择、设置、确认、进度窗按比例初始居中，保留应用尺寸约束。
- 音量、蓝牙、网络控制放右上；Firefox PiP 右下置顶、不抢焦点。
- 聊天主窗、IDE 工程、办公文档继续平铺；只有可区分标题的子窗才浮动。QQ、微信的登录窗和主窗标识可能相同，无法只靠规则区分，用 `Super+Space` 手动浮动。
- 没有固定工作区分配。`steam_app_*` 与 Minecraft 无边框、无阴影、无圆角。
- 一个平铺窗口或 monocle 贴住可用区域，不留边框和圆角。两个及以上窗口用 2 px 描边、16 px 圆角和 10/16 间距。开合窗口从 0.92 缩放并带透明度，工作区横向滑入，焦点在 120 ms 内过渡描边和 dim。数值在 [visual.md](visual.md)。

## 跨应用外观分工

| 应用 | 方式 |
|---|---|
| GTK3 / Thunar | adw-gtk3-dark；HM 把 One Dark CSS 渲染进 `gtk-3.0/gtk.css` |
| GTK4 | 保留 libadwaita 控件；HM 渲染 `gtk-4.0/gtk.css` |
| Qt | qt6ct + Fusion，只读 QSS，既有 GUI 偏好保留；Octave 是唯一的 Qt 5 应用，由 qt5ct 读同一 palette |
| KDE 组件 | `kdeglobals` 配色与图标（否则会回到亮色） |
| Firefox | 单一 seed 维护 `userChrome.css` 标记块，页面不反色 |
| Fcitx5 | SVG 主题，横排 7 项 |
| Kitty、btop、Yazi | HM 独占渲染 |
| Zathura、Obsidian | documents 自己渲染的 palette 文件/snippet |

Kitty 背景要和 Neovim `Normal` 同步（OSC 11），否则四周出现色框。

## 排障

- 主题改动后 Qt、输入法没变：`systemctl --user restart fcitx5-daemon.service`，已运行的应用要重开。
- `swaylock` 不能解锁：确认 host 侧 `security.pam.services.swaylock` 存在；锁屏中不要重启会话服务。
- HM 报 “would be clobbered by backing up”：目标旁已有 `*.backup`，先看内容，改名加时间戳，不删除。
- 服务重启失败：先查残留旧进程是否占着 D-Bus 名或单实例锁，结束后 `reset-failed` 再启动。

隔离截图与通用陷阱见 [operations.md](operations.md#隔离视觉验证)。旧版说明归档在 [history/README.md](history/README.md)（原文 `desktop-design-2026-10-30.md`）。
