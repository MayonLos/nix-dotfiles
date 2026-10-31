# nix-dotfiles

NixOS + Home Manager 配置，当前只有一个真实主机 `nixos-btw`（Intel + NVIDIA 笔记本）和用户 `mayon`。Home Manager 随 NixOS 重建，没有独立 switch。Mango 是默认桌面；`xorg-session` 提供可选 dwm + Picom 真 Xorg 会话。两种会话不同时运行。

仓库使用 Den 与 flake-parts。`aspects/default.nix` 显式登记功能，`bundles/default.nix` 用 Den `includes` 组合功能，`inventory/` 保存实体事实与选择。功能、契约、配方与资源集中在功能目录，目录不会被递归扫描。架构与仓库约定见 [AGENTS.md](AGENTS.md)，操作、回滚与验证层级见 [操作说明](docs/operations.md)。

## 目录

```text
flake.nix                 flake-parts 外层入口和锁定 inputs
nix/                      pkgs、host pipeline、outputs、checks、开发环境
aspects/system/            默认工具契约和系统维护
aspects/hardware/          机型驱动与策略
aspects/appearance/       外观数据、壁纸和头像
aspects/desktop/           session-support、Mango、Xorg、greeter
aspects/cli/               shell、terminal 与命令行工具
aspects/dev/               编辑器、语言、embedded、容器、虚拟机、AI agents
aspects/apps/              Firefox、通信、文档、媒体、文件管理、游戏
aspects/network/           网络管理和远程访问
aspects/workspace/         workspace-task 与 project-workbench
bundles/                   仅用 includes 组合已登记功能
inventory/                 用户身份、主机事实、绑定、秘密声明
lib/                       多功能共用的纯 helper
tests/composition/         跨功能组合、隔离和边界 fixture
secrets/                   sops 加密数据
docs/                      现行设计、操作和归属文档
```

Neovim Lua 配置和插件/parser 在 `aspects/dev/neovim/config/` 与同目录配方；`nix/outputs.nix` 通过公开包工厂导出 `.#neovim` 和 `.#neovim-dev`。外观数据、语言 collector、包工厂和测试钩子仅在对应功能 README 中声明为公开入口，其余功能内 Nix 文件是私有实现。

## 日常命令

```sh
nr                  # nh os switch --flake .#nixos-btw；会应用配置并一并重建 Home Manager
nc                  # nh clean all；运行前检查 generation 保留和待诊断产物
nix fmt             # 格式化 Nix 与 Lua（treefmt）
nix develop         # 开发 shell
nix develop .#cuda  # CUDA 开发 shell
```

求值和构建不会应用配置；`nixos-rebuild switch` 会更改运行系统。`nixos-rebuild test` 也会临时激活配置，不是只读检查。常用求值与构建命令：

```sh
nix flake check --no-build --no-write-lock-file
nix build --no-link --no-write-lock-file .#checks.x86_64-linux.treefmt
nix build --no-link --no-write-lock-file .#nixosConfigurations.nixos-btw.config.system.build.toplevel
```

构建通过只证明对应 derivation 成功；桌面、服务与设备行为需要配置应用后的实际验收。完整验证层级、回滚与清理说明见 [docs/operations.md](docs/operations.md)。

## 桌面与工作方式

Mango 管窗口、显示器、工作区和 Super 系列快捷键；Noctalia 提供面板、通知、启动器、控制中心与桌面剪贴板历史。固定主题为 One Dark，背景 `#1e2228`，壁纸不参与自动取色。完整按键以当前 [Mango 配置](aspects/desktop/mango-session/mango.nix) 为准。窗口规则集中在 [单一规则表](aspects/desktop/mango-session/mango/window-rules.nix)，覆盖 PiP、对话框、工具窗与游戏/通讯例外；用途和可调工作区默认见 [Mango README](aspects/desktop/mango-session/README.md#window-rules)。第二十一轮使用上游 Mango、2 px 蓝边与轻微非焦点 dim，顶栏常显 Fcitx 原生状态图标。终端内 tmux 使用 `Ctrl+a` 前缀；配置见 [tmux](aspects/cli/shell/tmux.nix)。

`workspace-project list` 列出显式绑定的项目；`workspace-task -- 命令 参数` 在命令运行期间阻止普通睡眠请求。项目工具链由项目自己的 flake 和 `.envrc` 管理，工作台不会创建项目目录或运行历史命令。剪贴板、会话服务与可变状态的唯一写入者见 [配置归属](docs/config-ownership.md) 和 [服务策略](docs/service-policy.md)。

## 编辑器与默认工具

真实 binding 将 CLI 与 GUI 默认工具分开：`EDITOR`/`VISUAL` 使用 Neovim，GUI 文本入口使用 VS Code；终端、浏览器和文件管理器通过 `default-tools` wrapper 传递 argv。

```sh
nix run .#neovim
NVIM_CONFIG_DIR="$PWD/aspects/dev/neovim/config" nix run .#neovim-dev
```

普通包使用 store 配置；开发包允许显式覆盖配置目录。插件、LSP、格式化、lint 和原生配置说明见 [Neovim 重建记录](docs/neovim.md)。

## 状态与秘密

HM 管理的 store 文件只读。应用偏好、历史、认证、模型、项目、容器卷和 VM 镜像属于用户状态；迁移配置不意味着清理这些数据。秘密通过 sops 运行时文件或模板提供，不进入 Nix 字符串、日志或 store。主机秘密声明位于 [`inventory/hosts/nixos-btw/secrets.nix`](inventory/hosts/nixos-btw/secrets.nix)，用户与主机绑定位于 `inventory/hosts/nixos-btw/users/mayon.nix`。

现行文档索引见 [docs/README.md](docs/README.md)；AI 和人都从这里按任务查找；过程记录在 `docs/history/`。
