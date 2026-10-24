# 操作与验证

本仓库的求值、构建、应用和实机验证是四个不同层级。前一层通过不代表后一层通过。Home Manager 随 NixOS system generation 一起重建；本仓库没有独立的 Home Manager switch。

## 验证层级

| 层级 | 示例 | 能证明什么 |
|---|---|---|
| 求值 | `nix flake check --no-build --no-write-lock-file` | Nix 模块与检查能完成求值；不构建所有 derivation，也不代表运行配置正确 |
| 构建 | 构建 checks、formatter 或 system toplevel | 对应 derivation 成功生成；不会激活配置或启动服务 |
| 应用 | `nr` / `sudo nixos-rebuild switch --flake .#nixos-btw` | 激活新的系统 generation，并随之切换 Home Manager generation |
| 实机 | 登录会话、冷启动应用、核对设备/服务/文件 | 仅能证明已实际执行并记录的具体行为 |

常用只读构建检查：

```sh
nix flake check --no-build --no-write-lock-file
nix build --no-link --no-write-lock-file .#checks.x86_64-linux.treefmt
nix build --no-link --no-write-lock-file .#nixosConfigurations.nixos-btw.config.system.build.toplevel
```

如需构建所有检查，可先列出当前 `checks.x86_64-linux` 输出，再显式构建各项。功能检查名由 `nix/checks.nix` 登记；`checks.architecture` 会在求值阶段执行，即使 `--no-build` 也应触发。不得把求值检查说成构建通过。

## 应用与回滚

`nr` 是 `nh os switch` 的快捷入口，flake 目录来自绑定的 `flakePath`，由系统 NH 配置提供，会改变运行系统。只有任务明确包含应用配置时才执行。`nixos-rebuild test` 也会临时激活配置，不能用作只读测试。切换前确认 `git status --short`、变更范围、目标输出和必要备份；新 generation 的成功不自动证明所有会话、服务和外设行为。

需要回退时可从启动菜单选择前一代系统，也可按机器现有 NixOS 操作流程使用 `sudo nixos-rebuild switch --rollback`。回退后仍需检查 system generation 与 Home Manager generation，并对有状态的应用确认实际文件和服务归属。不要用回滚替代应用数据备份。`nc` 对应 `nh clean all`，会清理旧 generations/store；执行前确认保留策略与待排查的构建结果，避免在回退和诊断所需内容尚未确认时清理。

## 未跟踪文件与临时快照

Git flake 源只包含 Git 跟踪文件。新建文件在由主代理纳入 Git 索引前不会进入 `.#` 的求值源；不要因此直接改用 `path:.`，它可能把 `.gitignore` 忽略的临时文件一起复制进 store。

确需临时诊断时，使用独立临时快照：以 `git ls-files` 的跟踪文件为基底，只追加本次需要验证且经过检查的未跟踪源码文件；过滤 `.git/`、`.work/`、`.team/`、`.worktrees/`、`result*`、运行时状态、私钥和所有秘密明文。先列出快照文件清单并检查内容边界，再从快照求值；快照结果只作诊断，不代替在已审阅、已纳入 Git 输入的源码上最终验证。不要把临时快照提交或写入用户数据目录。

## 当前重构状态

第八轮架构重构期间仅修改源码与文档，没有执行 `nixos-rebuild switch`、`nixos-rebuild test` 或独立 Home Manager 激活。architecture、全部 21 个 checks 与 toplevel 已通过过滤源码快照构建；基线和验证边界见[第八轮记录](history/architecture-v2-execution.md)。新文件仍需主代理审阅暂存并以 Git flake 复核。任何图形会话、设备、服务与登录流程都需要另行应用并进行对应实机验证。
