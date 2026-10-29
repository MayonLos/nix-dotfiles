# AGENTS.md

本仓库使用 Codex。以下路径均相对仓库根目录；配置依据当前源码、`flake.lock` 锁定源码和实际运行行为。Den 负责组合，不改变这一证据优先级。

## 仓库

NixOS + Home Manager，Den + flake-parts。当前真实实例为单主机 `nixos-btw`、用户 `mayon`：Intel + NVIDIA 笔记本，使用 Mango 桌面。Home Manager 随 NixOS 重建，没有独立 switch。

`xorg-session` 另提供可选 dwm + Picom 真 Xorg 会话，用于 QQ/腾讯会议等原生捕获；Mango 仍是登录默认项。两者不同时运行；入口、服务归属与待验项见 [`docs/xorg-desktop-execution.md`](docs/xorg-desktop-execution.md)。

| 路径 | 职责 |
|---|---|
| `flake.nix` | inputs 与 mkFlake 接线及 follows 策略 |
| `nix/default.nix`、`nix/den.nix` | flake-parts 导入和 Den schema/quirk 注册 |
| `nix/pkgs.nix` | stable/unstable 实例、`pkgs.unstable` 白名单、`pkgs.local` 第三方别名 |
| `nix/hosts.nix` | host schema 上的 `instantiate` 与 Home Manager 全局接线 |
| `nix/outputs.nix` | Neovim flake 包输出 |
| `nix/checks.nix` | 显式登记功能检查、组合检查和架构检查 |
| `nix/dev.nix` | 开发 shell、formatter 与质量工具 |
| `aspects/system/` | 默认工具 schema、系统维护 |
| `aspects/hardware/` | 机型驱动与策略（Legion 笔记本） |
| `aspects/appearance/` | 外观契约、主题数据、壁纸、头像功能 |
| `aspects/desktop/` | 会话支持、Mango、Xorg、greeter |
| `aspects/cli/` | shell、terminal 与 CLI 工具 |
| `aspects/dev/` | 编辑器、语言、embedded、containers、virtual machines、AI agents |
| `aspects/apps/` | browser、communication、documents、media、file manager、gaming |
| `aspects/network/` | laptop network、remote access |
| `aspects/workspace/` | workspace-task、project-workbench |
| `bundles/` | 只通过 Den `includes` 组成的常用功能组合 |
| `inventory/` | 实体、硬件事实、用户身份、绑定选择、秘密声明 |
| `packages/` | 自写程序源码只放在这里；功能目录通过公开包使用，负责安装、快捷键与配置 |
| `lib/` | 至少两个功能目录共同使用的纯 helper；不是模块发现器 |
| `tests/composition/`、`aspects/**/checks.nix` | 跨功能组合与功能检查 |
| `secrets/` | sops 加密数据 |
| `docs/` | 现行架构、操作、写入归属与服务策略；`docs/history/` 为执行记录 |

`aspects/default.nix` 显式登记 feature 入口。资源、模块和配方就近放在功能目录，不会递归扫描成为模块。`bundles/default.nix` 只通过 `includes` 组合已登记 feature。真实实例只在 `inventory/` 声明；测试 fixture 不属于可部署主机清单。

九个领域目录是导航分类，不代表依赖层级。aspect ID 与目录路径解耦，迁移目录时 ID 保持稳定。Xorg 专属模块、dwm 配方、启动脚本与测试集中在 `aspects/desktop/xorg-session/`。Mango 与 Xorg 只复用 `desktop/session-support`；`workspace-task` 是命令行与桌面共用的独立功能。Neovim Lua、插件/parser 与配置包位于 `aspects/dev/neovim/config/` 和同目录 `package.nix`、`plugins.nix`、`parsers.nix`；薄 flake 输出由 `nix/outputs.nix` 调用公开包工厂。

## 配置与数据边界

- stable 与 unstable nixpkgs 实例只在 `nix/pkgs.nix` 创建。功能通过 `pkgs.unstable.<白名单名>` 访问明确列出的例外，通过 `pkgs.local.<名称>` 使用第三方 flake 包的原始 derivation 别名。本仓库 Rust 工作区通过公开 `pkgs.mayonTui.{clash,docker,ports}` 输出使用；`packages/mayon-tui/default.nix` 是包工厂。不得重新导入 nixpkgs 或新增自建实例。
- `nix/hosts.nix` 经 `den.schema.host` 以 `mkDefault` 提供 `instantiate` 和 HM 全局接线。`homeManagerArgs` 先在 host schema 边界设默认值，再以普通优先级交给 HM，因为 HM 会以普通优先级添加 `nixosConfig`；避免浅层 attrs 合并丢失 host 的 `inputs` 与 `hostFacts`。不要把某台机器的事实闭包捕获进通用接线。
- 功能间只使用 `includes` 做选择，实体 schema 接收输入，quirk/pipe 传贡献，公开模块选项合并模块设置，公开包工厂接收参数。只可引用 feature 的 `default.nix`、`contract.nix` 或 README 明确列出的公开导出；其他 Nix 文件均为私有。
- 有契约、主机侧内容或拥有配置/用户状态的 feature 必须提供 `README.md`，说明用途、输入、输出、拥有文件和移除后的状态。`checks.nix` 是显式登记的测试钩子，不作模块发现。
- inventory 的布局为 `inventory/users/<user>.nix`（跨主机身份），以及 `inventory/hosts/<host>/{default,facts,hardware-configuration,secrets}.nix` 和 `inventory/hosts/<host>/users/<user>.nix`（host facts、扫描配置、秘密声明与用户绑定）。inventory 只写实体、数据与选择，不放 `pkgs`、脚本、activation 或业务模块实现。硬件扫描模块和秘密模块导入为明确例外。
- 秘密不能进入 Nix 字符串、日志或 store；通过 sops 运行时文件/模板交给消费者。配置/资源迁移不等于删除应用数据。保留项目、模型、历史、登录状态、容器卷及 VM 镜像。
- 修改 workaround 前先读原因，按当前锁定源码或实际行为核验；历史测量有时间范围。当前 `flake.lock` 与源码优先，发现矛盾时更新说明。
- 服务生命周期与配置 writer 归属分别遵循 [`docs/service-policy.md`](docs/service-policy.md) 和 [`docs/config-ownership.md`](docs/config-ownership.md)。

## 工作与验证

审核请求先给带路径和证据的发现，区分缺陷、可选改进和未验证推测。要求修改时完成实现、文档及相关验证。求值、构建、应用和实机验证是不同证据层级：不把前者写成后者。

```sh
git status --short
git diff --check
nix fmt                          # 会改文件；先查看已有改动
nix flake check --no-build --no-write-lock-file  # 求值，不证明构建成功
nix build --no-link --no-write-lock-file .#checks.x86_64-linux.treefmt
nix build --no-link --no-write-lock-file .#nixosConfigurations.nixos-btw.config.system.build.toplevel
```

按影响选择检查。纯文档检查链接、事实和格式；模块改动求值并构建相关输出；桌面/编辑器行为还需相应运行时证据。缺依赖或网络失败时报告限制，不宣称通过。Git flake 不含未跟踪文件；`path:.` 可能把 Git 忽略的本地文件带入 Nix store，使用前检查源范围，不能包含运行时秘密。临时求值新文件时只构造过滤后的源码快照，排除 `.work/`、`result*`、运行时状态与秘密明文。

构建不会应用配置。`nixos-rebuild switch` 会更改运行系统；只有任务明确包含应用配置时才执行。`nixos-rebuild test` 也会临时激活配置，不能当作只读构建检查。Home Manager 随 NixOS 一起重建，不支持独立 HM switch。系统入口为 `sudo nixos-rebuild switch --flake .#nixos-btw`（`nr`）；清理命令为 `nc`；开发环境为 `nix develop` 和 `nix develop .#cuda`。应用与回滚流程见 [`docs/operations.md`](docs/operations.md)。

## Codex 分工

主代理负责方案、跨功能判断、真实 host 接线、集成、最终核验和提交。把可独立完成的窄任务交给 Luna；跨模块结论由继承主模型的独立 reviewer 复核。使用当前环境原生子代理工具；项目角色尚未加载时，在任务中显式选择 `gpt-6-luna` 并说明角色要求，不假装角色已加载。若该模型不可用，由主代理接手。

每个子任务说明目标、绝对路径、可写范围、已知事实和验收标准。并行写任务分配不重叠文件；需改同一文件或独立 CLI 执行时使用隔离 worktree。子代理不得回滚他人改动、stage、commit 或 push；主代理审阅证据和 diff 后集成。结论须说明改动路径、实际验证与限制。

无需把 Codex 包装成外部 `codex exec`，不依赖家目录委托脚本。其他引擎仅在用户明确要求时使用，并单独确认上下文、权限及隔离范围。

用户要求“主代理设计审核、外部执行代理实现”时（例如 Claude 或 DeepSeek 作为主代理驱动 `codex exec`），按 [多代理工作流](docs/agent-workflow.md) 执行：预览先行、brief 模板、隔离 worktree、内存监控、隔离视觉验证、同会话续跑、集成与实机核对。
