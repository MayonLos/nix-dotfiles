# 系统界面与日常应用优化

日期：2026-10-18–19。起点 `da1f9ef`，工作树干净；承接用户“系统其他部分也优化美化”和继续查阅社区的要求。沿用 One Dark Darker、默认 Mango + Noctalia 及自主 nr 授权，后按用户要求加入 Hyprland 可选会话，不重复更换软件选择。Neovim 已有独立[重建记录](neovim-rebuild-execution.md)，本轮只处理其余系统界面。实际 Astra 负责桌面设计与四个视觉模块，Luna 负责 Yazi/tmux 和 mpv，主代理集成写入归属、CLI、构建、应用与文档；跨模块由独立 reviewer 复核。

## 设计与社区参考

实际浏览社区源码与作者展示：

- [Caelestia ActionItem](https://github.com/caelestia-dots/shell/blob/main/modules/launcher/items/ActionItem.qml)：主标题、次级描述和整行选择。采用可读列表启动器，保留分类、固定应用、命令/provider 搜索和键盘入口。
- [end-4](https://github.com/end-4/dots-hyprland#-screenshots-)：系统控制区与工作区域分离。本机采用右上控制中心和独立设备 OSD，沿用已有工作区/临时工具操作。
- [DMS](https://github.com/AvengeMedia/DankMaterialShell#screenshots)：实底表面与有限强调色。本机当前 006 壁纸较明亮且细节丰富，阅读浮层改实底，蓝色集中用于启动器和活动工作区。
- [uosc 5.12.0](https://github.com/tomasklaen/uosc/blob/5.12.0/README.md)：播放器时间线、菜单、播放列表与 thumbfast 缩略图配合，按当前固定版本实现。

社区配置作为设计依据；实际字段以 `flake.lock` 的 Noctalia/Mango、stable nixpkgs `7993f34` 和 Home Manager 锁定源码为准。没有运行社区安装脚本、引入第二套 shell、更新输入或增加壁纸 daemon。Hyprland 使用同一 stable nixpkgs 的 0.55.4，配置依据该版本原生 Lua 源码，不照搬旧版 hyprlang 示例。

## 实现

- Noctalia：680 宽列表启动器、右上控制中心、设备分区的紧凑导航、38 高面板；收敛重复胶囊，保留工具抽屉和全部入口。通知位于右上，OSD 移到下中，避免两类反馈争位。阅读浮层使用 `solid`，正文不会透出背后窗口文字。
- Mango：平铺窗口以焦点边框区分，软阴影只用于浮窗；取消非焦点暗罩以保持多文档对比度。保留已配置的窗口规则、概览、布局、临时工具和短动效，GTK 动画也跟随 `reducedMotion`。
- 锁屏与登录：锁屏补日期与留白，登录面板和 shell 统一圆角。当前 006 运行壁纸保留；009 只作为默认和 greeter 资源。greeter 新样式只在下次自然启动时显示，不通过重启 greetd 中断工作会话。
- 终端工具：Yazi 的模式、页签、指示条和选择标记使用共享 palette；预览指示增加下划线。tmux 宽窗口补充当前目录与窗口状态标记。Lazygit 用深色选区代替反色行，Bat 与 Delta 使用完整内置 `base16` 语法主题，消费终端 ANSI。
- mpv：使用固定 uosc 替换内置 OSC，保留 MPRIS、autoload、thumbfast、evafast；时间线、播放列表和菜单统一 OneDark，OSD/字幕使用适合数字/中文正文的字体。默认不对所有片源加载 Anime4K CNN；`Ctrl+1` 显式启用原 HQ 链，`Ctrl+0` 清空。未测量 GPU/功耗，不宣称性能或续航提高。

## 写入与数据边界

Yazi 的 `theme.toml` 从 Noctalia community template 交给 HM 唯一渲染：移除 `command-line.noctaliaIntegrations` 中的 `yazi`，保留 btop。应用前保留原公开主题的可回退副本，再交接生成目标；不删除其他 Yazi 配置/历史。Noctalia 可变公开 override 继续由原有限字段 helper 管理，不复制完整状态或秘密。

保留浏览器 profile/登录、Rime 学习库、shell/tmux 历史、项目、模型、容器卷和 VM 镜像。Firefox 路径审查中的初始“应改回 ~/.mozilla”判断已被事实否定：本机使用实际存在的 XDG profile，Firefox 新版本也支持 XDG，不按旧帮助页修改目录。没有迁移或重写浏览器 profile。

## 已应用的首批证据

CLI、媒体、桌面分为 `c681bfe`、`eb272b7`、`209bdbd` 三个本地提交。首批 17 个根 checks
构建通过，完整主机产物构建并 nr 应用为
`/nix/store/pgn48dw5imsvzp6vqngskck6vl6k6khc-nixos-system-nixos-btw-26.05.20261012.7993f34`。
这批尚未包含后续 Hyprland 与关闭热区的变更。

Yazi 原公开主题备份在
`~/.local/state/nix-dotfiles/theme-handoff/20261018-235810/yazi-theme.toml`（目录 0700、文件 0600），
仅在旧 Noctalia writer 优雅退出后交接；当前 `theme.toml` 为 HM symlink。Noctalia 已由 nr 恢复，
运行壁纸仍为用户所选 006。切换前后的 12 个受保护进程 PID/启动时间均一致，包括 Java/mod、
Codex、Mango、终端等；greetd、NetworkManager 和 nix-daemon 未重启。

在隔离 HOME/XDG 与自建测试视频中实际打开 mpv/uosc、中文字幕并截图；IPC 确认默认 shader
为空、evafast 的 RIGHT 优先绑定保留。对这份测试视频实际执行 uosc 删除命令，验证进入
测试目录 Trash 的 files/ 与 info/，没有对用户媒体执行删除。`use_trash=yes` 和 trash-cli
防止 uosc 默认永久删除。当前宿主既有 `nvdec-copy` 尝试未找到 CUDA 设备，测试回落软件解码；
本轮不声称硬解、GPU 或功耗优化已经验证。

## 用户追加的 Hyprland 与热区

修正了遗留 `BAT_THEME=Catppuccin Mocha` 与 Bat 的 OneDark/base16 声明冲突；旧桌面环境
保留到完整重登录，不把仅重开终端当成已刷新 HM 环境。按用户要求关闭右下热区，保留左下启动器。真实 mayon binding 明选新的 `hyprland-session`，
Mango 保持默认登录项。Astra 负责原生 Lua 视觉、窗口规则、键位和临时工具；主代理负责
host/Den 接线、Noctalia 配置变体、共享服务与截图分派，Luna 核验锁定接口和实现退出 wrapper。
独立 reviewer 在应用前发现并纠正：变体不能放在 Noctalia 自动合并的根目录；Mango clipboard
workaround 不能套到原生同步多 MIME 的 Hyprland；仅 Lua shutdown event 不能覆盖信号退出。

Noctalia/Fcitx/xrdb 随选定桌面 target，clipboard-bridge 仅随 Mango；PipeWire sockets 可由
任一所选会话请求。安装两个会话不等于支持同一 UID 同时运行两套 compositor。Noctalia
复用 HM 公开视觉资源和现有 state/data，变体只隐藏 Mango 专属插件；GUI 新建 palette 写入
只读变体目录不受支持，应通过声明修改，未迁移个人历史/壁纸数据。

实机截图在空工作区完成并恢复原工作区，保留当前 006 壁纸。实际 Astra 再次查看桌面、
列表启动器、右上音频控制分区和亮度 OSD，未发现可读性、裁切或重叠阻断；音频分区截图
不代表控制中心完整首页已验收，也不证明动效、键盘/悬停、通知或锁屏。截图为
`/tmp/codex-system-experience-{desktop,launcher-verified,control-verified,osd-verified}.png`，
属于本机临时证据，没有作为仓库资源上传。

## 最终构建与应用

- 本批代码提交：`29733cc`（BAT 环境）与 `1bfa548`（可选 Hyprland、热区、服务与截图整合）。
  全部 18 个 x86_64 根 checks 已实际构建通过；完整 `nixos-btw` toplevel 构建通过。
  首次完整检查只因 Statix 的 `inherit` 风格要求失败，修正后完整 18 项重跑成功。
- `sudo nixos-rebuild switch --flake …#nixos-btw` 返回 0，应用为
  `/nix/store/bqn51naqg7cbw0pvx6fy6r344dlr1c52-nixos-system-nixos-btw-26.05.20261012.7993f34`。
  `flake.lock` 未改，没有推送或手动 GC。旧 generation 与公开主题备份保留。
- 应用前后 15/15 个受保护进程 PID/启动时间一致；greetd PID 1742、NetworkManager 1149、
  nix-daemon 1212 均未变。nr 明确输出不重启 greetd。
- Mango target active，Hyprland target loaded/inactive；Noctalia 唯一 daemon PID 802071，
  Fcitx5 active、clipboard-bridge PID 2165 保留。WLR portal active、Hyprland portal inactive，
  新增桌面没有在当前会话启动第二套 compositor/backend。
- 实际 Noctalia merged 配置的右下 action 为 `none`、Mango 插件仍保留；运行壁纸不变。
  实际截图 dispatcher 返回 `mango`，mark-shot JSON 仅 command 交接，其他设置的规范化哈希一致。
  独立读取新 HM session-vars 的 `BAT_THEME=base16`，不声称旧桌面的继承环境已经刷新。
- 证据日志在 `/tmp/codex-hyprland-final-checks-retry.log`、
  `/tmp/codex-hyprland-final-host.log`、`/tmp/codex-hyprland-switch.log` 与
  `/tmp/codex-hyprland-apply-result.json`；日志与截图为本机临时产物。

## 尚待实机验收

Hyprland 冷登录、正常/TERM/INT 退出、NVIDIA
和外屏、截图/复制、锁屏恢复、屏幕共享仍须用户自然登录该会话后逐项验收，不能由 parser
或构建通过推断。当前 Mango 不因新增登录项而被重启或注销。实测既有 greetd 的启动命令固定旧
`XDG_DATA_DIRS` desktop store 目录；nr 不重启它，因此仅注销可能仍显示旧会话列表，
新 Hyprland 入口在下次系统重启或工作结束后单独重启 greetd 才可见。本轮不执行这些中断操作。
