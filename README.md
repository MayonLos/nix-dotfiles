# nix-dotfiles

NixOS + Home Manager 配置，当前只有一个真实主机实例 `nixos-btw`（Intel + NVIDIA 笔记本，
默认 Mango、可选 Hyprland 桌面）和用户 `mayon`。Home Manager 随 NixOS 重建，没有 standalone switch。

仓库使用 Den 与 flake-parts。`aspects/default.nix` 显式登记完整功能，`bundles/default.nix`
组合常用 `includes`，`inventory/` 描述真实主机、账号、事实和绑定参数。资源、模块 helper 与
软件配方都可放在所属 aspect 内；不会递归扫描目录。架构/操作约定见 [AGENTS.md](AGENTS.md)，
重构逐批实施、构建证据与运行态限制见[执行记录](docs/den-execution.md)。
后续窗口、临时工具层与视觉动效的实现和验收见[桌面优化记录](docs/desktop-polish-execution.md)。
系统/编辑器应用见[应用记录](docs/system-polish-execution.md)，最后一轮面板、场景和输入法
见[收尾记录](docs/panel-rime-execution.md)；最新 CLI、媒体、桌面与可选 Hyprland
见[系统界面记录](docs/system-experience-execution.md)，均区分构建、应用与用户验收。

## 目录

```text
flake.nix                 flake-parts 外层入口与锁定 inputs
nix/                      Den、nixpkgs、开发环境、包输出和 root checks
aspects/default.nix       显式登记所有 aspect
aspects/*/                完整功能、共享协议、renderer、资源和专项检查
bundles/default.nix       personal-desktop / engineering-workbench / remote-workspace 组合
inventory/hosts/          真实主机 facts、账号、绑定与系统入口
inventory/users/          用户级身份
lib/                      跨功能 helper
secrets/                  sops 加密数据
tests/composition/        跨 aspect 组合、隔离及边界 fixture
docs/                     架构、视觉、操作、归属、服务策略和迁移记录
```

常用代码入口：桌面与外观在 `aspects/interactive-session/`、`aspects/appearance/`；命令行、
Kitty 与 tmux 在 `aspects/command-line/`；丰富 Neovim Lua、插件和 parser 位于
`aspects/editing/neovim/`，薄包输出在 `nix/neovim.nix`。语言数据与工具在
`aspects/languages/`。容器、虚拟机、Firefox、媒体、游戏、AI、嵌入式等各自位于
`aspects/<feature>/`。

## 日常命令

```sh
nr                  # nh os switch --flake .#nixos-btw，含 Home Manager
nc                  # 清理旧 generation/store；运行前确认保留策略
nix fmt             # 格式化 Nix 与 Lua（treefmt）
nix develop         # git、gnumake、clang-tools、sops、age、ssh-to-age
nix develop .#cuda  # CUDA 开发 shell
```

求值和构建不会应用配置；`nixos-rebuild switch` 会更改运行系统。`nixos-rebuild test` 也会临时
激活配置，不是只读检查。host 输出：

```sh
nix flake check --no-build --no-write-lock-file
nix build --no-link --no-write-lock-file .#checks.x86_64-linux.treefmt
nix build --no-link --no-write-lock-file .#nixosConfigurations.nixos-btw.config.system.build.toplevel
```

按改动选择专项 check 并构建。构建通过只证明所检查的求值/产物；桌面、设备和服务行为需要
配置应用后的相应实机验收。

## 桌面与操作

Mango 默认负责窗口、显示器、工作区和 Super 系列快捷键；Noctalia 提供面板、通知、启动器、控制
中心与桌面剪贴板历史。固定主题是 One Dark Darker，背景 `#1f2329`，壁纸不改写配色。按
`Super+F1` 可打开当前配置生成的 Mango 快捷键说明；该说明从同一组 Nix 键位数据生成。

Hyprland 已作为独立登录选项配置，Mango 默认不变；本次不重启正在运行的 greetd，保存工作并在下次系统重启后，
可在登录屏幕选择 Hyprland。它复用 Noctalia/OneDark，常用快捷键对齐，`Super+F1` 同样提供当前键位帮助；
工作区 2 为原生 scrolling，其他默认 dwindle，详情见[操作说明](docs/workflow-design.md)。
右下鼠标热区已关闭，左下启动器保留。同一账号一次只运行一个 compositor。

终端内分工：所选 compositor 管桌面操作，tmux 使用 `Ctrl+a` 前缀，Neovim 保留自己的 Ctrl/leader 键。
tmux 有前缀导航：`h/j/k/l` 切换 pane，Tab 与 `n/p` 切换窗口，`1`–`9` 选窗口；旧的无前缀
Alt pane/window 截获已移除。输入完整快捷键与布局以 [Mango](aspects/interactive-session/mango.nix)
及 [tmux](aspects/command-line/tmux.nix) 当前配置为准。

`Super+Alt+D` 切换勿扰，`Super+Alt+I` 切换防空闲；面板铃铛与咖啡显示状态。
启动器提供“Nix 配置工作台”“NewNuclear 工作台”和“长任务终端”。
`workspace-project list` 列出显式项目，`workspace-task -- 命令 参数` 在命令运行期间
阻止普通睡眠请求；它与防空闲开关各有范围，详见[操作说明](docs/workflow-design.md)。

音量和日常混音由 Noctalia 控制中心管理。可用 `wpctl status`、`wpctl inspect ID` 查看实际
PipeWire 设备，再根据设备支持的 profile/route 查询结果操作，不照抄其他机器编号。`Super+V`
使用 Noctalia 原生剪贴板历史；Mango 的 X11/Wayland 剪贴板桥为跨协议应用保留，Hyprland 使用原生同步。配置迁移不删除已有
剪贴板历史数据库。

## 终端、工具与 Neovim

真实 binding 显式区分 CLI 与 GUI 默认工具：`EDITOR`/`VISUAL` 使用 Neovim，GUI 文本入口使用
VS Code；终端、浏览器和文件管理器经 `default-tools` wrapper 传递原始参数。

Neovim 原生 Lua 配置、插件集合与 Tree-sitter parsers 由 Nix 包固定。普通包使用 store 配置，
开发包允许覆盖配置目录：

```sh
nix run .#neovim
NVIM_CONFIG_DIR="$PWD/aspects/editing/neovim/config" nix run .#neovim-dev
```

普通包忽略 `NVIM_CONFIG_DIR`。Home Manager init 与包入口共用这套配置；完整 statusline、buffer
tabline、面包屑、LSP、completion、formatter、lint、会话等实现位于
`aspects/editing/neovim/config/`。主题采用共享 palette 数据生成，不用少量示例高亮覆盖 Lua
主题。界面按原 Nixvim 效果重新设计：固定 OneDark 完整主题、Heirline/Navic、Snacks 与
Markdown 渲染，替换此前自写组件。功能与最新验证见[重建记录](docs/neovim-rebuild-execution.md)。

## 服务与运行状态

声明式服务的 session 边界和所有权见 [服务策略](docs/service-policy.md)。删去旧模块不代表旧
Home Manager generation 中的 unit 或进程已经停止；切换前后都需按执行记录区分构建结果与当前
运行状态。用户已应用 Den 配置，后续系统/编辑器优化也获授权应用；实际交接、验证和未完成的
GUI 项目见[当前应用记录](docs/system-polish-execution.md)，不能把 nr 成功视作全部实机验收。

## 配置、状态和秘密

HM 管理的 store 文件只读。应用可写设置、用户偏好和历史需要按 feature 声明目录/文件所有权，
详见[写入归属](docs/config-ownership.md)。变更声明不自动删除项目、模型权重、登录 state、
剪贴板历史、容器卷或 VM 镜像。

API key 等秘密使用 sops-nix，秘密经运行时文件或模板交给消费者，不进入 Nix 字符串、日志或
store。机器密钥与编辑密钥的所有权和操作步骤见 [secret 接线](inventory/hosts/nixos-btw/credentials.nix)
及 `docs/config-ownership.md`。
