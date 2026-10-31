---
summary: 求值、构建、应用、回滚、清理的命令和四个验证层级
read_when: 需要验证改动、应用配置、回滚或清理；汇报验证结果前
code: [nix/checks.nix, nix/dev.nix, flake.nix]
checks: [treefmt, architecture, docs]
---

# 操作与验证

## 验证层级

报告时写明达到哪一层，不把前一层写成后一层。

| 层级 | 示例 | 能证明什么 |
|---|---|---|
| 求值 | `nix flake check --no-build --no-write-lock-file` | 模块和检查能求值；`checks.architecture` 在此触发 |
| 构建 | 构建 check 或 toplevel | derivation 能生成；不激活任何东西 |
| 应用 | `nr` | 切换系统与 Home Manager generation |
| 实机 | 登录、启动应用、核对设备和文件 | 只证明实际执行过的那个行为 |

## 常用命令

```sh
git status --short && git diff --check
nix fmt                                      # 会改文件
nix flake check --no-build --no-write-lock-file
nix build --no-link --no-write-lock-file .#checks.x86_64-linux.<名>
nix build --no-link --no-write-lock-file --print-out-paths .#nixosConfigurations.nixos-btw.config.system.build.toplevel
nix eval --no-write-lock-file --raw .#checks.x86_64-linux --apply 'c: builtins.concatStringsSep " " (builtins.attrNames c)'   # 列出全部检查
```

检查登记在 `nix/checks.nix`。内存：全系统求值 3–7 GB，全量 checks 可达 9 GB，同一时刻只跑一个；本机 31 GB。

## 应用与回滚

- `nr`（`nh os switch`）或 `sudo nixos-rebuild switch --flake .#nixos-btw` 会改变运行系统，只有任务明确包含应用时才执行。需要在真实终端输入密码。
- Home Manager 随系统一起切换，没有独立 switch。`nixos-rebuild test` 也会激活配置，不是只读检查。
- 应用后要手动处理的：Noctalia 不会自动重启（见 [desktop.md](desktop.md)）；合成器、greeter、内核相关改动要重新登录或重启。
- 回滚：启动菜单选上一代，或 `sudo nixos-rebuild switch --rollback`。之后核对 system 和 Home Manager generation。回滚不能替代应用数据备份。
- 清理：`nc`（`nh clean all`）会删旧 generation，确认不再需要回退和诊断后再用。

## 未跟踪文件

Git flake 只包含已跟踪文件，新文件 `git add` 后才进入求值。`path:.` 会把 `.work/` 等被忽略的文件带入 store，可能含秘密，不要用。确需临时诊断时，用 `git ls-files` 加显式文件构造快照，排除 `.git/`、`.work/`、`.team/`、`.worktrees/`、`result*`、运行时状态和秘密。

## 用户数据

配置迁移不等于删除数据。项目、模型、历史、登录状态、容器卷和 VM 镜像都要保留；移除功能时只撤回声明，数据是否清理由用户决定。
