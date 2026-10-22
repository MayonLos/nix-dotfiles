# 仓库整理与会话边界

2026-10-19。用户选定 DWM 的 B 方案后，要求全仓整理、多子代理并行，并遵守现有 Den 架构。
B 的可回退提交为 `e44a21b`，前一轮登录修复为 `5566788`；目录整理以前者为基线，实现在 `64b1b52`。
本轮不应用系统、不更新启动默认 generation、不 push，不删除应用数据或停止业务进程。

## 全仓审查结论

主代理负责集成；Luna 分别审查跟踪文件/资源、生产架构调用、检查与文档索引；独立 reviewer
检查跨模块结论。已核对显式 registry、bundles 的 includes、inventory 事实/绑定、nix 薄接线、
lib 共享消费者与 tests 入口。没有确认到应删除的跟踪缓存或死资源。

壁纸被 Noctalia 的目录随机选择使用，wallpaper-009 还供 greeter/Xorg 使用；词库、
Neovim 配方、现有组合检查和 Codex 角色也各有消费者，保留。有日期的历史审查记录仍是
历史证据，不按“没有自动导入”判断为垃圾。没有扫描或清理家目录数据。

修正两处真实调用问题：

1. Xorg 的 Den includes 原先带入整个 Mango/Noctalia；target guard 只能约束启动，不能
   消除声明耦合。现由两种实现各自 include 实际共用的 `graphical-session-support`。
2. 桌面入口原先直接 import CLI 私有的 task 配方。现由 `workspace-task` 公开功能交给
   CLI 与共享会话分别选择；配方与 sleep inhibitor 范围保持原样，桌面从用户 profile 调用。

没有创建后端 registry、万能 renderer 或递归模块发现器。`bundles/` 仍只组合 includes，
真实主机与绑定仍在 inventory；未添加服务器或修改锁输入。

## 文件归属

```text
aspects/
├── command-line/                  # CLI，仅选择公共 workspace-task
├── workspace-task/
│   ├── default.nix                # 窄功能的显式注册
│   └── package.nix                # 保持原行为的长任务命令配方
└── interactive-session/
    ├── default.nix                # Mango/Xorg/公共支持的 Den 关系
    ├── host/portal-common.nix     # GTK/GNOME Settings/keyring 基础支持
    ├── host/portal.nix            # Mango 的 wlroots 路由和输出策略
    ├── service.nix               # 仅本会话功能组复用的 unit helper
    ├── input-method.nix / qt.nix  # 实际共享的输入与 Qt 初始配置
    └── xorg/
        ├── default.nix / host.nix # Xorg HM/宿主实现
        ├── runtime.nix / session  # 启动、退出、环境和生命周期
        ├── ui.nix / appearance.nix / lock.nix / tools.nix
        ├── dwm/                  # 源码 pin、生成配置与本地修正
        ├── checks.nix            # 功能检查入口
        └── tests/                # 隔离 supervisor、QQ wrapper、桌面行为
```

旧的 `xorg-*.nix`、顶层 dwm 与 `resources/xorg/test_*.py` 路径通过移动退出，没有兼容转发层。
Xorg 与 Mango 的运行逻辑仍各自拥有，不把它们改成字符串选择的通用脚本。
`nix/checks.nix` 只接入功能入口；跨功能组合仍在 `tests/composition/`。
图形服务 helper 的三个消费者都在会话功能组内，故由顶层 `lib/` 移回本组 `service.nix`；
真正跨功能复用的 seed、语言工具链等 helper 继续留在 `lib/`。

## 写入与组合约束

Wayland 工具与 `NIXOS_OZONE_WL=1` 只由 Mango 选择。输入法、xrdb、GTK/Qt、音频、字体和
基础 portal 由公共支持拥有，具体 capture 路由归会话。独立 Xorg 不依赖 Noctalia 首次运行
生成 Qt 配色；缺失时 seed 公共 OneDark 初始值，保留原路径、既有 GUI 设置和 runtime writer。
配置 seed 不持续覆盖用户文件，详见[写入归属](../config-ownership.md)。

新增组合负例覆盖“仅 Xorg”的账号/主机：应具有 Xserver/startx/PAM、输入法、Qt/GTK、
Picom/Dunst 与 Xorg target；不应具有 Mango、Noctalia、Wayland clipboard、Mango target、
wlroots capture portal 或 Wayland Ozone 环境。旧强依赖关系会使这些负例失败。
真实笔记本仍同时选择 Mango 与 Xorg；默认登录仍是 Mango，Xorg 展示名为 DWM。

## 验证状态

已实际执行并通过：

- 完整 `nix flake check --no-write-lock-file --max-jobs 1 --cores 2`，包括全部根 checks；
  日志 `/tmp/codex-repository-checks-verified.log`。锁定 Den 导出的 `denful` 名称仍有 Nix 的
  unknown-output 提示，不影响检查返回 0，不为消除此提示删除框架输出。
- 完整 `nixos-btw` toplevel 构建，日志 `/tmp/codex-repository-system-verified.log`；系统输出
  `/nix/store/r8ly0x2p8qdbqxxjm14glpd90zw39b11-nixos-system-nixos-btw-26.05.20261012.7993f34`。
- 十项桌面组合结果全部为 true，包括独立 Xorg 的正/负边界。实际运行 Xorg-only Qt palette
  seed：验证三组各 22 个颜色、OneDark 值，并确认第二次执行保留已有 GUI 内容。
- Xorg supervisor、中文 j4/dmenu 应用选择/参数、菜单取消/未知输入、浮动与全屏恢复、
  Dunst 与 Picom XRender 隔离检查。输出
  `/nix/store/9n399q5igqcx657dic8chcashsppgc4z-xorg-session-runtime`。
- Astra 实际目检最终 144 DPI 截图：原生栏完整可见，标签/布局/标题/状态无重叠，
  中文通知与浮窗符合 B。截图只保存在检查输出，不将生成图重复加入 Git。
- 三十份 Markdown 的相对链接检查通过。独立 reviewer 复核调用、生命周期和 Qt seed，
  未发现剩余阻断问题。配方/helper 移动前后字节一致；`flake.lock` 未改。

完整检查前曾发现新文件的格式问题，定向修正后重新执行整套检查通过；不将失败轮当成通过。
构建不等于应用。本轮没有 switch/boot/test、重启会话、GC 或 push；当前运行仍是用户此前
启动的 generation 394。真实 DWM 登录恢复尚未再次验证，不能从 isolated Xvfb 推断。
