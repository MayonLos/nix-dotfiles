# hyprland-session

实验性第三桌面会话：**Hyprland 合成器 + Noctalia Shell**，用于在同一台主机上比较
Mango（默认）、Umbriel 与 Hyprland 三种会话。默认登录项仍是 Mango；本目录不改
`mango-session` 与 `umbriel-session` 的任何文件，三个会话在 greeter 的选择器里并存。

## 用途与边界

- **合成器**：Hyprland 0.55.4（stable nixpkgs 的 `pkgs.hyprland`，hyprlang 配置时代）。
  0.57 起改为 Lua 配置格式，本仓库的 `monitor = eDP-1, 2560x1600@165, 0x0, 1.5` 与
  `bind = MODS, key, dispatcher, args` 写法不兼容，因此不使用 nixpkgs-unstable 的
  Hyprland（也避免为一个实验会话扩大 `pkgs.unstable` 白名单）。
- **Shell**：Noctalia v5.6.0，与 Umbriel 会话共用同一份 `noctalia.nix`（顶栏、启动器、
  通知、OSD、锁屏、壁纸、剪贴板面板、控制中心、系统监视）。Umbriel 的 `luciole.nix`
  一并复用，文件管理器仍是全用户 MIME 默认（Mango 会话的 Thunar），本实验不动它。
- **登录**：沿用仓库的 greetd + gtkgreet，host 侧通过 `nixDotfiles.extraLoginCommands`
  注入第三个登录命令；gtkgreet 在命令数 >1 时显示选择器。
- **会话服务**：`graphical-session-support` 的 fcitx5、GTK/Qt、X resources 等服务同时挂到
  `mango-session.target`、`umbriel-session.target` 与 `hyprland-session.target`。
- **systemd target**：`hyprland-session.target` 由 Home Manager 的 Hyprland 模块在
  `systemd.enable = true` 时定义，因此本目录没有 `session.nix`；再定义一次只会重复
  `Description`/`BindsTo`。HM 的默认 `systemd.extraCommands` 会在注入的 exec-once 里
  `stop`+`start` 该 target，本 feature 另外在 exec-once 里幂等地 `start` 一次。

## 输入

- `host.appearance`（仓库 One Dark palette：边框色、光标、动画开关 `reducedMotion`）；
- `host.facts.display`（输出名、分辨率、刷新率、scale，写入 Hyprland `monitor` 规则）；
- `pkgs.local.noctaliaDesktop`（Noctalia 实验包工厂，见 `packages/noctalia-desktop/`）；
  `../umbriel-session/{noctalia,luciole}.nix` 是 umbriel-session README 列出的公开导出
  （同时登记在 `nix/checks.nix` 的 `publicFiles`），本 feature 直接复用而不是 fork；
- `pkgs.local.mark-shot` 与 HM profile 里的 `workspace-files`/`workspace-browser`/
  `ocr-screen`/`ocr-region`（后两者由 Mango 会话的 `screenshot.nix` 安装，Home Manager
  是用户级共享的，所以 Hyprland 会话里同样可用）。

## 输出与拥有文件

| 路径 | 写入者 |
|---|---|
| `~/.config/hypr/hyprland.conf` | 本 feature（Home Manager 生成，hyprlang） |
| 用户 systemd：`hyprland-session.target` | Home Manager 的 Hyprland 模块（`systemd.enable`） |
| `~/.config/noctalia/config.toml`、`~/.config/noctalia/palettes/one-dark.json` | 复用 `../umbriel-session/noctalia.nix` |
| `/etc/xdg/xdg-desktop-portal/hyprland-portals.conf` | NixOS `xdg.portal.config.hyprland`（`host.nix`） |
| `/etc/greetd/environments` 的第三个登录命令 | `aspects/desktop/greeter/greeter.nix`（`-c` 条目 + `extraLoginCommands`） |
| 系统侧的 compositor/portal 包、`~/.config/hypr/` 之外的 XWayland | NixOS `programs.hyprland`（`host.nix`） |

Noctalia 运行时写入的应用数据（`~/.local/state/noctalia/`、`~/.cache/noctalia/`）归程序所有；
本 feature 不清理、不移除。

## 设计取舍

- **portal 归 NixOS 模块**：`host.nix` 打开 `programs.hyprland`，由它装
  `xdg-desktop-portal-hyprland` 并写 `/etc/xdg/xdg-desktop-portal/hyprland-portals.conf`。
  HM 侧因此把 `wayland.windowManager.hyprland.portalPackage` 设为 `null`：默认值会让
  HM 打开自己的 `xdg.portal`，把 `NIX_XDG_DESKTOP_PORTAL_DIR` 指向 HM profile 的
  portals 目录（`NIX_XDG_DESKTOP_PORTAL_DIR` 在 nixpkgs 的 xdg-desktop-portal 补丁里是
  **替换**而非追加），Mango/Umbriel 依赖的 wlr/gtk 后端会因此从所有会话里消失。
- **配置格式固定为 hyprlang**：`home.stateVersion = 25.11` 让 HM 26.05 的 `configType`
  默认仍是 `hyprlang`，这里显式写出，避免以后跟随 HM 默认值无声切换成 Lua。
- **命令用绝对路径**：greetd 启动会话时环境近乎为空，登录脚本按仓库其他会话的做法
  只把 `/run/current-system/sw/bin` 与 `$HOME/.nix-profile/bin` 放进 PATH；因此
  `noctalia`、`polkit-gnome`、`kitty`、`fuzzel`、`mark-shot` 用 store 路径，
  仓库脚本用 `${config.home.profileDirectory}/bin/*`，不依赖登录环境 PATH。
- **Super 单击启动器**：Mango/Umbriel 的“Mod 单击”在 Hyprland 里用
  `bindr = SUPER, Super_L, ...`（release bind）。按住时普通 press bind 永远匹配不上
  `SUPER+Super_L`：`CKeyboard` 在触发 keybind 之后才调用 `updateXkbStateWithKey`，
  Super 的 modifier 位在 Super_L 的 press 事件里尚未生效；release 时已经生效，且按住
  Super 期间触发的其他 bind 会 shadow 掉它，所以只有“按下并松开 Super、期间没有触发
  其他 bind”才会打开启动器（Hyprland 源码里的注释就给出了这个写法）。
  等价入口还有 Noctalia 顶栏与 `ALT+Space`（fuzzel）。

## 风格

沿用当前桌面的取向而不是社区模板：One Dark 单 seed（边框 `#61afef` / `#5c6370`）、
gaps 8、1px 边框、圆角 0、无阴影、blur 仅 `size = 3, passes = 1` 的轻量档；顶栏仍是
Noctalia 的 30px 全透明样式（与 Umbriel 共用配置）。键位镜像 Mango/Umbriel 的核心集合
（SUPER 启动器、SUPER+Return/E/B、HJKL 与方向键聚焦/移动、数字工作区、
Print 截图族、硬件键走 Noctalia OSD 并允许锁屏时使用）。

## 移除后状态

删除本目录、`aspects/default.nix` 登记、`inventory/hosts/nixos-btw/users/mayon.nix` 里的
`hyprland-session` include 后，`programs.hyprland` 与第三个登录命令一并消失，会话回到
Mango + Umbriel 两项；用户侧的 Noctalia 配置、`~/.config/hypr/` 与状态目录保留
（不自动删除）。三个会话共用的 fcitx/GTK/Qt 服务仍由 `graphical-session-support` 提供。

## 验证状态

- 求值：`nix eval .#nixosConfigurations.nixos-btw...toplevel.drvPath` 通过
  （`/nix/store/fyhfbwkkcgfx64ygnvbv5dixmi132l7a-nixos-system-nixos-btw-26.05.20261113.f1e5c35.drv`）。
- 构建：`nix build .#nixosConfigurations.nixos-btw...toplevel` 通过，toplevel 为
  `/nix/store/nbpiij7afllnb26jgb92ijyryh8nag5i-nixos-system-nixos-btw-26.05.20261113.f1e5c35`。
- 静态配置校验：对生成的 `hyprland.conf` 运行 `Hyprland --verify-config -c FILE`，
  输出 `config ok`（Hyprland 0.55.4 解析的是 hyprlang）。
- 嵌套测试：在当前 Umbriel 会话里以 nested Wayland backend 起了 Hyprland，加载的配置
  只去掉 `exec-once`；实例正常启动、`hyprctl configerrors` 为空，`hyprctl binds` 列出
  52 条 `bind`、9 条 `bindl`、1 条 `bindr`（共 62 条），`getoption` 确认
  `general:border_size = 1`、`decoration:blur:enabled = true`、`input:kb_layout = us`。
  嵌套输出 `WAYLAND-1` 的 refresh 是 60Hz 而不是 `eDP-1`，所以 monitor 规则里的
  `2560x1600@165`/scale 1.5 没有被覆盖。
- 运行时：**尚未通过 greetd 登录实机验证**；三会话真实对比数据未测。首次登录后需确认
  Super 单击启动器、Noctalia 在 Hyprland 下读取 workspace/active-window、锁屏 OSD。
