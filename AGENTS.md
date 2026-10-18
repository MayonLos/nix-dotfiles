# AGENTS.md

本仓库使用 Codex。以下路径均相对仓库根目录；配置依据当前源码、`flake.lock`
锁定源码和实际运行行为。Den 负责组合，不改变这一证据优先级。

## 仓库

NixOS + Home Manager，Den + flake-parts。当前真实实例为单主机 `nixos-btw`、用户
`mayon`：Intel + NVIDIA 笔记本，使用 Mango 桌面。Home Manager 随 NixOS 重建，没有独立
switch。

| 路径 | 职责 |
|---|---|
| `flake.nix`、`nix/` | 输入、Den/flake-parts 接线、nixpkgs、开发 shell、Neovim 输出、检查 |
| `aspects/` | 完整功能、系统策略、外观/语言/工具协议及各自的配方和资源 |
| `bundles/` | 仅用 Den `includes` 组成的常用功能组合 |
| `inventory/hosts/`、`inventory/users/` | 真实主机硬件与账号事实、绑定参数、秘密接线和个人身份 |
| `lib/` | 少量跨功能 helper；不是模块发现器 |
| `tests/composition/`、`aspects/*/checks.nix` | 跨功能组合与功能内构建/行为检查 |
| `secrets/` | sops 加密数据 |
| `docs/` | 架构、操作、写入归属、服务和执行记录 |

`aspects/default.nix` 显式登记 aspect 模块；资源和 Nix 配方可就近放在功能目录，
不会通过递归扫描自动变成模块。`bundles/default.nix` 只通过 `includes` 组合已登记
aspect。真实实例只在 `inventory/` 声明；测试 fixture 不属于可部署主机清单。

Neovim 原生 Lua、插件/parser 与包定义在
`aspects/editing/neovim/config/` 与同目录 `package.nix`、`plugins.nix`、`parsers.nix`；薄 flake 包输出位于
`nix/neovim.nix`。

## 配置与数据边界

- `pkgs` 默认来自 stable `nixos-26.05`；`pkgs-unstable` 只用于既有明确例外或 stable
  确实不能满足的包。两者和 `inputs` 的接线见 `nix/nixpkgs.nix` 与 host instantiate。
- 不给 `mango`、`noctalia-greeter`、`mark-shot`、`wayscrollshot`、`llm-agents`
  添加 `follows`：其源码依赖组合或预构建缓存依赖各自的 pin。
- 秘密不能进入 Nix 字符串、日志或 store；通过 sops 运行时文件/模板交给消费者。
- 修改 workaround 前先读原因，按当前锁定源码或实际行为核验；历史测量有时间范围。
  当前 `flake.lock` 与源码优先，发现矛盾时一并更新说明。
- 配置/资源迁移不等于删除应用数据。保留项目、模型、历史、登录状态、容器卷及 VM
  镜像；不得为清理旧声明而清除它们。

## 工作与验证

审核请求先给带路径和证据的发现，区分缺陷、可选改进和未验证推测。要求修改时完成
实现、文档及相关构建验证。求值、构建、应用和实机验证是不同证据层级：不把前者写成
后者。

```sh
git status --short
git diff --check
nix fmt                          # 会改文件；先查看已有改动
nix flake check --no-build --no-write-lock-file  # 求值，不证明构建成功
nix build --no-link --no-write-lock-file .#checks.x86_64-linux.treefmt
nix build --no-link --no-write-lock-file .#nixosConfigurations.nixos-btw.config.system.build.toplevel
```

按影响选择检查。纯文档检查链接、事实和格式；模块改动求值并构建相关输出；桌面/编辑器
行为还需相应运行时证据。缺依赖或网络失败时报告限制，不宣称通过。Git flake 不含未跟踪
文件；`path:.` 可能把 Git 忽略的本地文件带入 Nix store，使用前检查源范围，不能包含运行时
秘密。

构建不会应用配置。`nixos-rebuild switch` 会更改运行系统；只有任务明确包含应用配置时才
执行。`nixos-rebuild test` 也会临时激活配置，不能当作只读构建检查。系统入口为
`sudo nixos-rebuild switch --flake .#nixos-btw`（`nr`）；清理命令为 `nc`；开发环境为
`nix develop` 和 `nix develop .#cuda`。

## Codex 分工

主代理负责方案、跨功能判断、真实 host 接线、集成、最终核验和提交。把可独立完成的窄任务
交给 Luna；跨模块结论由继承主模型的独立 reviewer 复核。使用当前环境原生子代理工具；项目
角色尚未加载时，在任务中显式选择 `gpt-6-luna` 并说明角色要求，不假装角色已加载。若该模型
不可用，由主代理接手。

每个子任务说明目标、绝对路径、可写范围、已知事实和验收标准。并行写任务分配不重叠文件；
需改同一文件或独立 CLI 执行时使用隔离 worktree。子代理不得回滚他人改动、stage、commit
或 push；主代理审阅证据和 diff 后集成。结论须说明改动路径、实际验证与限制。

无需把 Codex 包装成外部 `codex exec`，不依赖家目录委托脚本。其他引擎仅在用户明确要求时
使用，并单独确认上下文、权限及隔离范围。
