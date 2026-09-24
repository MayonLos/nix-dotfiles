# AGENTS.md

本仓库使用 Codex。这里是常驻上下文；领域知识放在 `.agents/skills/`，
只读取当前任务涉及的技能及其相关 references。以下路径均相对仓库根目录。

## 仓库

NixOS + Home Manager，flake-parts，单主机 `nixos-btw`，用户 `mayon`。
Intel + NVIDIA 笔记本，mango 桌面。Home Manager 随 NixOS 重建，无独立 switch。

| 路径 | 职责 |
|---|---|
| `flake.nix`、`flake/` | 输入、主机接线、开发 shell、格式检查 |
| `hosts/nixos-btw/` | 主机入口及硬件扫描配置 |
| `modules/system/`、`modules/home/` | 自动导入的 NixOS / Home Manager 模块 |
| `nixvim/` | 显式导入的 Neovim 模块树 |
| `pkgs/`、`lib/` | 自定义包与 `importDir` 辅助函数 |
| `secrets/` | sops 加密数据 |

## 不能在整理中丢失的约束

- `importDir` 递归加载 `modules/` 下**所有** `.nix`，没有跳过目录机制。
  helper、包表达式、nixvim 模块不能放进去。模块采用函数形式。
- `pkgs` 默认是 stable `nixos-26.05`；`pkgs-unstable` 只用于现有明确例外或
  stable 确实不能满足的包。两者和 `inputs` 的接线见 `nix-modules`。
- 不给 `mango`、`noctalia-greeter`、`mark-shot`、`wayscrollshot`、`llm-agents`
  添加 `follows`：其源码依赖组合或预构建缓存依赖各自的 pin。
- 秘密不进入 Nix 字符串、日志或 store；使用 sops 的运行时文件 / 模板。
- 修改 workaround 前先读原因，并按当前锁定源码或实际行为验证；旧测量不是永恒结论。
  `flake.lock` 和模块优先于技能里记载的旧版本，发现矛盾时一起更新说明。

## 技能路由

编辑相关领域前读取对应入口；跨领域只加载必要的几份。

| 技能 | 何时读取 |
|---|---|
| [nix-modules](.agents/skills/nix-modules/SKILL.md) | 模块增删移动、flake 接线、通道、开发 shell |
| [sops-secrets](.agents/skills/sops-secrets/SKILL.md) | 秘密增删轮换、凭据传递与运行时缺失 |
| [nvim-config](.agents/skills/nvim-config/SKILL.md) | `nixvim/` 插件、加载、键位及编辑器行为 |
| [dev-toolchain](.agents/skills/dev-toolchain/SKILL.md) | LSP、formatter、DAP、语言工具链、Emacs |
| [editors-ide](.agents/skills/editors-ide/SKILL.md) | JetBrains、VS Code、AI CLI 的安装与包装 |
| [shell-terminal](.agents/skills/shell-terminal/SKILL.md) | zsh、环境变量、kitty、tmux、yazi、git |
| [desktop-mango](.agents/skills/desktop-mango/SKILL.md) | mango、noctalia、portal、截图、剪贴板、fcitx5 |
| [desktop-apps](.agents/skills/desktop-apps/SKILL.md) | GTK/Qt/字体、默认应用、Thunar、媒体、IM |
| [gaming-stack](.agents/skills/gaming-stack/SKILL.md) | Steam、gamescope、gamemode、MangoHud、Prism |
| [host-hardware](.agents/skills/host-hardware/SKILL.md) | 内核/NVIDIA、虚拟化、内存、网络、系统服务 |

## 工作与验证

审核请求先给带路径和证据的发现，区分缺陷、可选改进和未验证推测。
要求修改时完成实现与相关验证；文档迁移不顺带切换系统或升级输入。

```sh
git status --short
nix fmt                          # 会改文件；检查已有用户改动后再运行
nix flake check --no-build --no-write-lock-file  # 求值，不证明构建成功
nix build --no-link --no-write-lock-file .#checks.x86_64-linux.treefmt
nix build --no-link --no-write-lock-file .#nixosConfigurations.nixos-btw.config.system.build.toplevel
```

按影响选择检查：纯文档检查链接、事实和格式；模块改动求值并构建相关输出；
编辑器/桌面行为还需运行时验证。缺依赖或网络失败时报告限制，不宣称通过。
新文件未被 Git 跟踪时，Git flake 看不到；可用 `path:.` 检查工作树，
但它也可能将 Git 忽略的本地文件纳入 Nix store，使用前检查源范围，不能包含运行时秘密。

系统切换命令是 `sudo nixos-rebuild switch --flake .#nixos-btw`（`nr`）；
清理是 `nc`；开发环境为 `nix develop` 和 `nix develop .#cuda`。
只有任务包含应用配置时才切换系统；构建本身不会应用配置。

## Codex 分工

主代理负责方案、跨模块判断、集成和最后核验。把能独立完成的窄任务交给
Luna：定点搜索、文档核对、小范围修正、明确范围的审查；不要为简单一步操作拆团队。

- `.codex/agents/luna-review.toml`：只读证据收集与小范围审核。
- `.codex/agents/luna-worker.toml`：有明确文件归属和验收条件的小改动。
- `.codex/agents/reviewer.toml`：独立复核，继承主代理模型，适合跨模块结论。

使用当前环境的原生子代理工具；客户端尚未发现项目角色时，在任务中显式选择
`gpt-6-luna` 并传入角色要求，不假装角色已加载。若该模型不可用，报告并由主代理接手。
每个子任务说明目标、绝对路径、可写范围、已有事实和完成标准；不要把猜测当结论传入。
并行写任务分配不重叠的文件；需改同一文件或独立 CLI 执行时使用隔离 worktree。
子代理不得回滚他人改动、提交或推送；主代理核对证据与 diff 后交付。
子代理结论须说明做了什么、改了哪里、实际验证与剩余限制。

无需把 Codex 再包装成外部 `codex exec`，也不依赖家目录的委托脚本。
其他引擎仅在用户明确要求时使用，并单独确定上下文、权限及隔离范围。
