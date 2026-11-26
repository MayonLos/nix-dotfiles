---
summary: 三个可登录会话（Mango/Umbriel/Hyprland）共享 Noctalia shell 的桌面组成、服务与外观分工
read_when: 修改顶栏、通知、OSD、壁纸、锁屏、启动器、窗口规则、会话选择或应用主题接线
code: [aspects/desktop/mango-session, aspects/desktop/umbriel-session, aspects/desktop/hyprland-session, aspects/desktop/noctalia-shell, aspects/desktop/noctalia-benchmark, aspects/desktop/session-support, aspects/desktop/greeter]
checks: [desktop-composition, mango-blur-sampling, unified-noctalia-session, greeter-tech, gtk-qt-theme]
---

# 桌面

登录器（greetd + Noctalia Greeter，实验分支默认；可切回 gtkgreet）列出三个可选会话：**Mango**（默认）、**Umbriel**、**Hyprland 0.55.4**。三个会话共享同一份 Noctalia v5 shell 和同一套 input method / GTK / Qt 会话支持；合成器只负责窗口管理、键位和窗口规则。参数值见 [visual.md](visual.md)，按键见 [keymap.md](keymap.md)，文件归属见 [config-ownership.md](config-ownership.md)。

## 共享 Shell（Noctalia）

- **顶栏**：Noctalia 的 30px 全透明栏（一个配置服务所有会话）。左侧工作区/窗口标题，右侧托盘、网络、电池、`CPU`/`MEM` 标签、中文时间；CPU 与内存只保留这两个采样器，GPU/网络/磁盘轮询为 0。
- **启动器与面板**：`Alt+Space` 打开 Noctalia launcher；`Super+V` 打开剪贴板历史面板；`Super+W` 打开壁纸面板；`Super+Escape` 打开会话面板。没有 Dock、Launchpad 或第二套启动器。
- **通知与 OSD**：Noctalia 统一绘制通知、音量/亮度/麦克风 OSD 和键盘锁定提示。媒体键之外的硬件键在三个合成器里都通过 Noctalia IPC 转发，不再有 swayosd。
- **壁纸与锁屏**：Noctalia 绘制壁纸；`Super+Alt+L` 调用 Noctalia 锁屏，通过登录 PAM 栈认证。没有 swaybg/sweetbgd/Matuwall/swaylock/swayidle。
- **优化配置**：`shell.offline_mode = true`（关闭 palette/天气/定位的周期 HTTP）、关闭 weather/calendar/community templates/screen time、剪贴板历史上限 50、动画跟随 `palette.reducedMotion`。生成配置在应用前用 `noctalia config validate` 校验。

## 会话

- **Mango**：默认会话，保留 mark-shot 的 Mango 窗口识别与拖拽吸附（`mmsg`）。`mango.nix` 负责配置、键位和窗口规则；`screenshot.nix` 只有 mark-shot 与 OCR，全屏截图走 Noctalia。窗口规则见 `mango/window-rules.nix`（文件选择、设置、确认、进度窗按比例居中；聊天/IDE/办公继续平铺；只有可区分标题的子窗浮动；QQ/微信登录与主窗用 `Super+Space` 手动浮动）。超级键（Super+Shift+...）与 Mango 的 tag/scratchpad 语义保留。
- **Umbriel**：wlroots + scenefx 合成器，滚动布局；配置在 `umbriel-session/umbriel.nix`。Noctalia 的 layer blur 规则沿用；键位镜像 Mango 主要入口。
- **Hyprland**：stable nixpkgs 的 0.55.4，hyprlang 配置（0.57 起改 Lua，未采用）；HM 模块负责 `hyprland-session.target`、portal 和环境导入。键位、截图和硬件键与 Mango 对齐。
- **登录选择**：greeter 只显示 store 路径列表，Mango 为默认项；三个会话的身份变量（`XDG_CURRENT_DESKTOP`/`XDG_SESSION_DESKTOP`）由各自登录脚本导出。

## 服务

三个合成器在启动 session target 前都会把 `WAYLAND_DISPLAY`/`XDG_SESSION_TYPE` 导入 systemd user manager，因此同一套 unit 在三个会话里都可用：

- `noctalia.service`（`Type=notify`）、`polkit-gnome-authentication-agent-1.service`、`clipboard-bridge.service` 由 `mango-session.target`、`umbriel-session.target`、`hyprland-session.target` 共同 `WantedBy`。
- `desktop-benchmark.service` 在登录后 90s/300s 写 idle 快照到 `~/.local/state/noctalia-bench/`，用于三个合成器同脚本比较（`Type=exec`，不阻塞 HM activation）。
- fcitx5、GTK/Qt、X resources 由 `graphical-session-support` 挂到三个 target。
- 生命周期与重启策略见 [service-policy.md](service-policy.md)；配置写入者见 [config-ownership.md](config-ownership.md)。

## 窗口规则（Mango）

唯一规则表是 `aspects/desktop/mango-session/mango/window-rules.nix`，字段以锁定 Mango 的解析器为准。规则按顺序覆盖；`app_id` 与 `title` 同写时是 AND，标题变化后不重新匹配。`steam_app_*` 与 Minecraft 无边框、无阴影、无圆角；一个平铺窗口或 monocle 贴住可用区域，两个及以上窗口按 [visual.md](visual.md) 的描边/圆角/间距绘制。开合、工作区滑动和焦点过渡数值在 visual.md。

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
- 锁屏不能解锁：确认 Noctalia 锁屏通过登录 PAM 栈认证；锁屏中不要重启会话服务。
- 某个会话没有顶栏：`systemctl --user status noctalia.service`，确认该 session target 已 active 且 unit 没被 `reset-failed` 挡住。
- HM 报 “would be clobbered by backing up”：目标旁已有 `*.backup`，先看内容，改名加时间戳，不删除。
- 服务重启失败：先查残留旧进程是否占着 D-Bus 名或单实例锁，结束后 `reset-failed` 再启动。

隔离截图与通用陷阱见 [operations.md](operations.md#隔离视觉验证)。旧版说明归档在 [history/README.md](history/README.md)。
