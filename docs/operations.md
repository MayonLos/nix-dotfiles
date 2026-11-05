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

## 隔离视觉验证

不在用户的 Wayland 会话里开窗口、模拟按键，也不重启 noctalia、fcitx5、mango 等桌面守护进程。

| 对象 | 方式 |
|---|---|
| Wayland 应用（Kitty、Neovim、GTK/Qt、文件选择器） | 私有无头 sway：`WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1`，独立 `XDG_RUNTIME_DIR`（路径要短，超过 `sun_path` 起不来）、`WAYLAND_DISPLAY`、`HOME`/XDG 与 D-Bus 会话；输出 2560×1600、scale 1.5；`grim` 指定该 socket 截图 |
| 终端界面 | 必须用真实 Kitty（放进上面的无头 sway）。tmux→HTML 转换看不出内边距、字体图标、背景色差异 |
| Noctalia 模板 | 运行锁定 Noctalia 的真实模板引擎，确认输出写出且无 template error；只检查模板文本会漏掉运行时失败 |
| 设计稿 | HTML 用 nixpkgs chromium `--headless=new --screenshot` 渲染；`html{zoom:1.5}` 对应实机 1.5 缩放 |

验证要先在旧版本上复现问题：新版“通过”本身不是证据。

## 已知陷阱

桌面相关陷阱（Noctalia 锁屏、主题、服务）见 [desktop.md](desktop.md#排障)。

- **补丁型美化**（Mango、Noctalia 源码补丁）每个都配构建期检查，上游升级时失败而不是静默退化。
- **独显断电**：用户常主动给 NVIDIA 断电，`nvidia-smi` 报 No devices 属正常。
- **zsh**：交互 shell 是 zsh，`$var` 不按空格拆分、没有 `$PIPESTATUS`；`pkill -f`/`pgrep -f` 的模式会匹配自己的命令行。多 PID 操作用 bash 脚本。
- **`git worktree remove --force`** 会删掉其中被忽略的 `.work/`，要保留的产物先拷出。
