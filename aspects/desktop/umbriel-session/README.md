# umbriel-session

实验性第二桌面会话：**Umbriel 合成器 + Noctalia Shell**，用于在 `work/noctalia-desktop`
分支上整桌面试用并与现有 Mango/mangobar 桌面做实际数据比较。默认登录项仍是 Mango；本目录
不修改 `mango-session` 的任何文件，两个会话在 greeter 的选择器里并存。

## 用途与边界

- **合成器**：Umbriel（wlroots + `umbrielfx`，scrolling/dwindle/master/stacking 布局、
  每输出工作区、窗口规则、blur/阴影/动效、HDR/VRR、layer-shell、会话锁）。
- **Shell**：Noctalia v5.6.0，负责顶栏、启动器、通知、OSD、锁屏、壁纸、剪贴板面板、
  控制中心、系统监视。Mango 会话里的 mangobar/mako/fuzzel/swayosd/swaylock/swaybg/cliphist-tui
  在 Umbriel 会话中不启动，由 Noctalia 对应部件替代。
- **文件管理器**：Luciole 随会话安装（Mango 会话仍是 Thunar；MIME 默认是全用户共享的，
  本实验不动它）。Umbriel 的 portal 后端会优先使用 Luciole 的文件选择器。
- **登录**：沿用仓库的 greetd + gtkgreet。`greeter.nix` 增加了 `extraLoginCommands` 选项，
  本 feature 通过 host 侧注入第二个登录命令；gtkgreet 在命令数 >1 时显示选择器
  （单会话隐藏选择器的本地补丁只在恰好一个命令时生效）。
- **会话服务**：`graphical-session-support` 的 fcitx5、GTK/Qt、X resources 等服务同时挂到
  `mango-session.target` 与 `umbriel-session.target`，两个会话都能用；Mango 专属单元仍然只挂
  `mango-session.target`。

## 输入

- `host.appearance`（仓库 One Dark palette，用于 Noctalia 自定义 palette、光标、字体）；
- `host.facts.display`（输出名与 scale，写入 Umbriel `[output.<name>]`）；
- `pkgs.local.noctaliaDesktop`（实验包工厂，见 `packages/noctalia-desktop/`）。

## 输出与拥有文件

| 路径 | 写入者 |
|---|---|
| `~/.config/umbriel/config.toml` | 本 feature（Home Manager 生成，TOML） |
| `~/.config/noctalia/config.toml`、`~/.config/noctalia/palettes/one-dark.json` | 本 feature |
| 用户 systemd：`umbriel.service`/`umbriel-session.target` 等 | Umbriel 包（`systemd.packages`） |
| `/etc/greetd/sway.conf` 的 gtkgreet 命令列表 | `aspects/desktop/greeter/greeter.nix`（新增 `-c` 条目） |
| 系统包与 portal | `host.nix`（`environment.systemPackages`、`xdg.portal`） |

Noctalia 运行时写入的应用数据（`~/.local/state/noctalia/`、`~/.cache/noctalia/`）归程序所有；
本 feature 不清理、不移除。

## 公开导出

以下两个文件在 `nix/checks.nix` 的 `publicFiles` 里登记为公开导出，供
`aspects/desktop/hyprland-session/` 复用；改签名时两个会话需要同步：

- `noctalia.nix`：`{ palette }` → Noctalia 配置、One Dark palette v2 与壁纸；
- `luciole.nix`：安装 Luciole 文件管理器。

`umbriel.nix`、`host.nix` 仍是本 feature 私有的合成器/登录实现。

## 风格

沿用当前桌面的取向而不是社区模板：One Dark 单 seed 转成 Noctalia palette v2（16 角色 +
ANSI）、顶栏高 30、`background_opacity = 0`（完全透明）、无边框/无阴影/无圆角、左侧只放工作区、
中间窗口标题、右侧托盘/网络/电池/CPU/RAM/时钟；面板与 OSD 用 Noctalia 默认但关闭边框，
blur 只对面板层开启。Umbriel 关闭 title bar 与特效，保留 blur radius 3。

## 移除后状态

删除本目录、`pkgs.local.noctaliaDesktop` 别名、`aspects/default.nix` 登记、
`inventory` 里的 `umbriel-session` include 与 `greeter.nix` 的 `extraLoginCommands` 用法后，
会话回到单 Mango 桌面；用户侧的 Noctalia/Umbriel 配置与状态目录保留（不自动删除）。
两个会话共用的 fcitx/GTK/Qt 服务仍由 `graphical-session-support` 提供。

## 验证状态

- 求值：实验分支 `nix eval .#nixosConfigurations.nixos-btw.config.system.build.toplevel.drvPath` 通过。
- 构建：见 `docs/history/README.md`（本实验单独记录）；Noctalia/Umbriel/Luciole/portal 的
  构建证据在 `.work/research/noctalia-pkgs-status.md`（只读调研产物，不入库）。
- 运行时：**尚未登录实机验证**；两个会话的真实对比数据未测。
