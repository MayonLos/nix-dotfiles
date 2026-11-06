---
summary: Mango + Noctalia 桌面的组成、窗口规则和跨应用外观分工
read_when: 修改顶栏、Dock、面板、通知、锁屏、窗口规则或应用主题接线
code: [aspects/desktop/mango-session, aspects/desktop/session-support, aspects/desktop/greeter]
checks: [desktop-composition, mango-blur-sampling, noctalia-osd-pixels, noctalia-template-runtime, greeter-tech, gtk-qt-theme]
---

# Mango + Noctalia 桌面

参数值见 [visual.md](visual.md)，按键见 [keymap.md](keymap.md)，文件归属见 [config-ownership.md](config-ownership.md)。功能细节和补丁清单在 [Mango README](../aspects/desktop/mango-session/README.md)。

## 组成

- **顶栏**：左侧启动器、当前应用名、工作区；中间留空；右侧托盘（内联）、网络、蓝牙、电池、未读通知、控制中心、中文日期时间。状态图标正常为 brightFg，断开才灰色。
- **Dock**：Smart，空工作区显示，有窗口收起，碰底边唤出；全屏窗口（含游戏）会盖住底边触发条，不会误触；固定 kitty、firefox、obsidian、thunar、code、qq、musicfox。
- **插件**：只有本仓库的 Launchpad、desktop-menus、legion-conservation，不用社区插件。
- **启动器**：`Alt+Space` 是原生应用搜索，`Super+A` 是 Launchpad。
- **夜灯**：关闭且没有入口。
- **壁纸**：`~/Pictures/Wallpapers/managed` 只读内置，`local/` 归用户，Noctalia 递归扫描两者。

## 服务

Noctalia 由 systemd 用户服务唯一启动。它设了 `X-SwitchMethod=keep-old`，`nixos-rebuild switch` **不会**重启它，补丁或配置改动要手动重启：

```sh
loginctl show-session <id> -p LockedHint   # 必须是 no，锁屏时重启会灰屏
systemctl --user restart noctalia.service
```

Mango 配置用 `mmsg dispatch reload_config` 重载。

## 窗口规则

唯一规则表是 `mango/window-rules.nix`，字段以锁定 Mango 的解析器为准。规则按顺序覆盖；`app_id` 与 `title` 同写时是 AND，标题变化后不重新匹配。

- 文件选择、设置、确认、进度窗按比例初始居中，保留应用尺寸约束。
- 音量、蓝牙、网络控制放右上；Firefox PiP 右下置顶、不抢焦点。
- 聊天主窗、IDE 工程、办公文档继续平铺；只有可区分标题的子窗才浮动。QQ、微信的登录窗和主窗标识可能相同，无法只靠规则区分，用 `Super+Space` 手动浮动。
- 没有固定工作区分配。`steam_app_*` 与 Minecraft 无边框、无阴影、无圆角。

## 跨应用外观分工

| 应用 | 方式 |
|---|---|
| GTK3 / Thunar | adw-gtk3-dark，Noctalia 独占生成 CSS |
| GTK4 | 保留 libadwaita 控件，只给语义色 |
| Qt | qt6ct + Fusion，只读 QSS，既有 GUI 偏好保留 |
| KDE 组件 | `kdeglobals` 配色与图标（否则会回到亮色） |
| Firefox | 单一 seed 维护 `userChrome.css` 标记块，页面不反色 |
| Fcitx5 | SVG 主题，横排 7 项 |
| Kitty、btop、Yazi | HM 独占渲染，不用 Noctalia 模板 |
| Zathura、Obsidian | documents 拥有的原色模板 |

Kitty 背景要和 Neovim `Normal` 同步（OSC 11），否则四周出现色框。

## 排障

- 主题改动后 Qt、输入法没变：`systemctl --user restart fcitx5-daemon.service`，已运行的应用要重开。
- Noctalia 起不来（start-limit-hit）：有不在服务 cgroup 下的手动实例，`kill -TERM` 后 `systemctl --user reset-failed noctalia.service`。
- HM 报 “would be clobbered by backing up”：目标旁已有 `*.backup`，先看内容，改名加时间戳，不删除。
- 锁屏时重启 Noctalia 会灰屏：它持有 ext-session-lock 锁屏面，重启后锁被遗弃。`noctalia.service` 已设 HM `X-SwitchMethod = "keep-old"`（`X-RestartIfChanged` 只对 NixOS 系统服务有效）。手动重启前先 `loginctl show-session <id> -p LockedHint` 确认为 `no`；已出现时用 `WAYLAND_DISPLAY=<该会话 socket> noctalia msg session lock` 重新接管。
- 服务重启失败：先查残留旧进程（旧 `.fcitx5-wrapped`、旧 noctalia）是否占着 D-Bus 名或单实例锁，结束后 `reset-failed` 再启动。
- Noctalia 自定义颜色：深色模式下 `colors.<name>` 是 Material 色调 80，原色用 `colors.<name>_value`；内置模板拿不到 `custom_colors`，要在构建主题资源时写入原色。

隔离截图与通用陷阱见 [operations.md](operations.md#隔离视觉验证)。旧版说明归档在 [history/desktop-design-2026-10-30.md](history/README.md)（原文 `desktop-design-2026-10-30.md`）。
