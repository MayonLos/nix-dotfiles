# 多代理工作流：主代理设计审核，执行代理实现

本文记录本仓库已经实际跑通的“主代理设计 + 审核、执行代理实现 + 自验”的工作方式，供 Claude、Codex、DeepSeek 等任何模型直接照做，用户不必每次重新说明。仓库规则仍以 [AGENTS.md](../AGENTS.md) 为准；本文只规定协作流程。

## 1. 角色

| 角色 | 职责 | 不做 |
|---|---|---|
| **主代理**（与用户对话的模型） | 理解需求、调研、出设计与预览图、写执行说明（brief）、监控、审核截图与 diff、合并、提交、应用配置、实机核对、向用户汇报 | 不把大段实现自己写完；不跳过审核直接合并 |
| **执行代理**（Codex `codex exec` 或其他 CLI 代理） | 在指定工作树内实现、写测试、构建、在隔离环境截图并迭代、给出带证据的最终回复 | 不提交、不应用配置、不碰用户会话 |
| **执行代理的子代理** | 并行改**互不重叠**的文件；最后一个独立 reviewer 复核 | 不并行跑 nix 求值/构建 |

用户的明确偏好：主代理负责设计，执行交给执行代理；视觉相关先给预览图，确认后再实现。回复使用中文；技术标签（布局名、键名、模式名等）保持英文原名。

## 2. 一轮任务的完整流程

1. **澄清与调研**：读当前源码、`flake.lock` 锁定源码与实际运行行为；必要时查社区。只问真正需要用户决定的问题，并给出推荐项。
2. **设计与预览**（视觉任务必做）：写 HTML 设计稿，用 nixpkgs 的 chromium headless 渲染成 PNG，再用 `swayimg` 给用户看。多张图分别开窗口，不要只放进一个窗口靠翻页。
   ```sh
   C=$(nix eval --raw --impure --expr '(builtins.getFlake "/home/mayon/nix-dotfiles").inputs.nixpkgs.legacyPackages.x86_64-linux.chromium.outPath')/bin/chromium
   $C --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
      --window-size=2560,1600 --screenshot=out.png file:///path/design.html   # 设计稿里 html{zoom:1.5} 对应实机 1.5 缩放
   setsid swayimg out.png >/dev/null 2>&1 &
   ```
   字形注意：Material Design 图标区（如 `󰉋 󰢱 󱄅`）在 chromium 中可渲染；部分旧 Nerd Font 码位不显示，会让用户误以为“没有图标”。
3. **写 brief**（模板见第 4 节），保存到会话临时目录，同时备份到 `.work/`（见第 7 节）。
4. **建隔离工作树**：并行轮次各用一个 worktree，互不改同一文件。
   ```sh
   git worktree add -b <branch> /home/mayon/nix-dotfiles-<name> HEAD
   ```
5. **启动执行代理**（第 5 节），挂监控（第 6 节）。
6. **审核**：读最终回复 → 看截图（逐张对照设计稿）→ 看 `git diff --stat` 与关键文件 → 必要时自己在隔离环境复现。发现问题就在**同一会话**里续跑（`resume`），不要另起会话丢上下文。
7. **集成**：在分支上提交 → 合并进 `main`（解决冲突时保留双方意图，修正冲突引起的断言）→ 全量求值 + 全部 checks + toplevel 构建 → 应用 → 实机核对（截图、日志）。
8. **汇报**：完成了什么、实机验证结果、尚未验证或无法实现的项、需要用户操作的事（如重新登录）。

## 3. 硬性约束（写进每个 brief）

- 执行代理**禁止**：`sudo`、`nixos-rebuild`、`git add/commit/push/stash/reset`、`nix flake update`、修改工作树外文件（临时目录除外）、删除用户数据（项目、模型、历史、登录状态、容器卷、VM 镜像、Templates/书签等）。
- **不得在用户的 Wayland 会话里开窗口或模拟按键**（会抢焦点，用户正在打字时按键会进到错误窗口）；**不得启动/重启用户的桌面守护进程**（noctalia、fcitx5、mango 等）。
- **内存**：本机 31 GB；单次全系统求值 3–7 GB，全量 checks 构建可达 9 GB。每个执行代理同一时刻最多 1 个 `nix build`/`nix flake check`；子代理不得并行跑 nix；同时运行的执行代理一般不超过 3 个，并由监控脚本在内存不足时冻结（第 6 节）。
- 新文件未被 Git 跟踪时，求值使用过滤后的源码快照（排除 `.work/`、`result*`、运行时状态与秘密），不要直接用会带入忽略文件的 `path:.`。
- 结论只写实际执行过的验证；求值 ≠ 构建 ≠ 应用 ≠ 实机。

## 4. Brief 模板

```text
你是执行代理。工作目录：<绝对路径>（分支 <name>，基于 <commit>），只在此目录工作。
另有代理在 <路径> 做 <内容>，不要碰；不要改 <禁止触碰的文件>。先读 AGENTS.md、<相关 docs 与源码>。

第 N 轮：<标题>。用户原话：“<原话>”。

## 设计依据（用户已确认，唯一视觉依据）
<设计稿 HTML/PNG 绝对路径>；用户问题截图：<路径>。

## 任务
1. ……（每项写清：目标、已知根因/证据、验收标准）

## 约束与验证
- 第 3 节全部硬性约束。
- 视觉验证：在隔离环境运行真实程序截图（第 8 节），至少 3 轮“截图→对比设计稿→修正”，存 <截图目录>。
- 测试：新增/更新 checks 断言关键行为。
- 最终：git diff --check、nix fmt、nix flake check --no-build --no-write-lock-file、
  受影响 checks、最后一次全部 checks + toplevel（--print-out-paths）。

## 最终回复
逐项结果、截图路径、无法实现项与替代、命令与结果、toplevel 路径、待实机验收项。不宣称未执行的验证。
```

追加任务（同一会话续跑）只写差异：“在本轮成果基础上继续，约束不变。1. … 2. …”。

## 5. 启动与续跑执行代理

### Codex

运行目录放在仓库内被 Git 忽略的 `.work/run-<日期>/`（**不要放 `/tmp`**：`/tmp` 是 tmpfs，重启即清空）。

```sh
S=/home/mayon/nix-dotfiles/.work/run-<日期>
cd <工作树> && setsid -f codex exec -c 'service_tier="default"' [-m <模型>] -C <工作树> \
  -o $S/codex-final-N.md - < $S/codex-brief-N.md > $S/codex-N.log 2>&1
grep -a -m1 "session id" $S/codex-N.log           # 记下会话 ID
# 同一会话续跑（追加任务、修问题、被中断后恢复）：
cd <工作树> && codex exec -c 'service_tier="default"' resume <session-id> -o $S/codex-final-N.md - < $S/codex-brief-Nb.md
```

- 服务档位：`~/.codex/config.toml` 全局写着 `service_tier = "fast"`（用户不希望改该文件）。用户要求暂不用 fast，命令行一律 `-c 'service_tier="default"'` 覆盖；`"flex"` 会被服务端拒绝（`Unsupported service_tier: flex`）。
- 模型：默认 `gpt-6.1-sol`；用户点名时用 `-m gpt-6-astra`（Neovim 自主精修轮使用）。
- 额度用尽时日志出现 `You've hit your usage limit`，额度通常 1–2 小时内重置：等待后 `resume` 同一会话，不要换引擎。
- 非 Git 目录需加 `--skip-git-repo-check`。
- 日志丢失时，会话 ID 可在 `~/.codex/sessions/<年>/<月>/<日>/rollout-*.jsonl` 中按 `"cwd":"<工作树>"` 找回。
- 执行代理在 `codex exec` 中途提问不会等待回答：把答复写成续跑 brief，等它本段结束后 `resume`（可用后台脚本等 `events.log` 中出现新的 `[N EXIT]` 再自动续跑）。
- 现成脚本：`.work/run-2026-10-25/fns.sh` 提供 `run <名> <目录> <brief> <codex 参数...>`，内含额度用尽每 20 分钟重试、内存冻结、事件写入 `events.log`；`launch.sh`、`run-*.sh` 是调用示例。

### 其他代理（如 DeepSeek 驱动的 CLI 代理）

同样的 brief 原样可用。要求：能在指定目录读写文件、运行 shell、长时间后台运行并输出最终回复到文件。没有子代理能力时，把 brief 中“子代理并行”改为顺序执行；没有会话续跑能力时，续跑 brief 需带上“上一轮最终回复”全文作为上下文。

## 6. 监控与内存保护

每个执行代理挂一个监控脚本：关键错误告警、退出通知、内存不足时先结束其 `nix` 子进程再冻结（SIGSTOP），内存恢复后解冻（SIGCONT）。

```bash
#!/usr/bin/env bash
S=<会话临时目录>; K=/run/current-system/sw/bin/kill
P=$(cat $S/codex-N.pid); L=$S/codex-N.log
( tail -n0 -F $L 2>/dev/null | grep --line-buffered -E "at capacity|rate limit|unexpected status 401|stream error|panicked" | sed -u "s/^/[rN ALERT] /" ) &
desc() { echo $1; for c in $(pgrep -P $1); do desc $c; done; }
frozen=0
while kill -0 $P 2>/dev/null; do
  a=$(awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)
  if [ $frozen = 0 ] && [ $a -lt 4500 ]; then
    for c in $(desc $P); do [ "$(ps -o comm= -p $c 2>/dev/null)" = nix ] && $K -TERM $c; done
    sleep 2; $K -STOP $(desc $P) 2>/dev/null; frozen=1; echo "[rN FROZEN] mem ${a}MB"
  elif [ $frozen = 1 ] && [ $a -gt 12000 ]; then
    $K -CONT $(desc $P) 2>/dev/null; frozen=0; echo "[rN RESUMED] mem ${a}MB"
  fi
  sleep 10
done
echo "[rN EXIT] final=$(test -s $S/codex-final-N.md && echo yes || echo no)"
```

注意：
- 用 PID 监控，不要用 `pgrep -f '<模式>'` 等待——模式字符串出现在自己的命令行里会自我匹配；同理 `pkill -f` 可能杀掉自己的 shell。
- 监控脚本用 bash 执行（交互 shell 是 zsh，数组与通配行为不同）。
- 监控有时长上限，到期后重新挂上同一脚本即可。

## 7. 临时文件与持久化

- 设计稿、brief、截图、执行代理日志直接放仓库内被 Git 忽略的 `.work/`（如 `.work/run-<日期>/`、`.work/<轮次>/shots/`），不要放 `/tmp`（重启清空）。维护一份交接文件（各轮会话 ID、工作树、阶段、待决事项）。
- 用户要重启/重新登录前：停掉衔接脚本 → 结束执行代理的 nix 子进程 → 结束执行代理 → 备份临时目录。恢复后从备份还原到原路径，再 `resume`。

## 8. 隔离视觉验证（不碰用户会话）

| 对象 | 方式 |
|---|---|
| Wayland 应用（Kitty、Neovim、GTK/Qt 应用、文件选择器） | 私有无头 sway：`WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1`，独立 `XDG_RUNTIME_DIR`、`WAYLAND_DISPLAY`、`HOME`/XDG 目录与 D-Bus 会话；输出 2560×1600、scale 1.5；`grim` 指定该 socket 截图 |
| X11/dwm 会话 | 私有 `Xvfb :97 -screen 0 2560x1600x24 -dpi 144`，独立 HOME/XDG；picom 用 xrender 后端；ImageMagick `import -window root` 截图；结束时清理全部进程 |
| 终端界面 | 必须用**真实 Kitty**（在上面的无头 sway 中）。tmux→HTML 转换看不出 Kitty 内边距、字体图标、背景色不一致等问题 |
| Noctalia 模板 | 运行锁定 Noctalia 的真实模板引擎检查输出文件被写出且无 template error；只检查模板文件内容会漏掉运行时失败 |

主代理自己做实机核对时：截图用 `grim`；**不要**在用户桌面上直接打开测试窗口（会抢焦点），需要看应用就放进上面的隔离环境。

## 9. 应用配置与实机核对（仅主代理）

```sh
sudo nixos-rebuild switch --flake .#nixos-btw
systemctl --user restart noctalia.service fcitx5-daemon.service   # 外观/输入法改动后
```

- 重启后若服务失败：先查是否有残留的旧进程占着 D-Bus 名或单实例锁（如旧 `.fcitx5-wrapped`、旧 noctalia），结束残留进程后 `systemctl --user reset-failed` 再启动。
- 合成器（Mango）、greeter、内核相关改动需要用户重新登录/重启才生效，要明确告诉用户。
- 核对 Noctalia 日志：`~/.cache/noctalia/noctalia.log` 中不应出现应用后的 `failed to render template`。

## 10. 已知陷阱（来自实际排查）

- **Noctalia 5.3 自定义颜色**：深色模式下 `colors.<name>` 是 Material 色调 80（浅色），原色要用 `colors.<name>_value`；内置模板（builtin_ids）渲染时拿不到 `custom_colors`，必须在构建主题资源时直接写入原色。
- **Kitty 与 Neovim 背景**：Kitty 背景与 Neovim `Normal` 背景不同会在四周出现色框；用 OSC 11 同步背景并在退出时恢复，tmux 需 `allow-passthrough on`。
- **KDE/Qt 应用**：不读 qt6ct 配色时会出现浅色菜单与无图标，需要 `kdeglobals` 配色与图标主题；文件对话框统一走 xdg-desktop-portal。
- **补丁型美化**（Mango、Noctalia 源码补丁）有维护成本；每个补丁必须配构建期检查，上游升级时失败而不是静默退化。用户不需要的效果（如焦点外发光）宁可删除。
- **zsh 陷阱**：交互 shell 是 zsh，`$var` 不按空格拆分（kill 多个 PID 用数组或 bash 脚本）；`pkill -f`/`pgrep -f` 的模式会匹配到自己的命令行，可能杀掉当前 shell。
- **Home Manager 激活失败 “would be clobbered by backing up”**：目标文件旁已有 `*.backup`。先查看两份内容，把旧 `.backup` 改名加时间戳（不删除），再重新 switch。
- **锁屏中重启 Noctalia 会“灰屏”**：Noctalia 持有 ext-session-lock 锁屏面；锁屏时它被重启（例如 switch 激活或手动 `systemctl --user restart`），锁会被遗弃，Mango 只显示纯色且无法用密码解开（2026-10-29 实际发生）。现在 noctalia.service 设了 Home Manager 的 `X-SwitchMethod = "keep-old"`，switch 不再停止或重启它（`X-RestartIfChanged` 只对 NixOS 系统服务有效，HM 用户服务会忽略，2026-10-29 曾因此误判）；手动重启前先 `loginctl show-session <id> -p LockedHint` 确认为 no。已经出现时：`WAYLAND_DISPLAY=<该会话的 wayland-N> noctalia msg session lock` 让该会话的 Noctalia 重新接管，再切回该 tty 输入密码。
- **Noctalia 服务起不来（start-limit-hit / “Noctalia is still running”）**：有不在服务 cgroup 下的手动启动实例；`kill -TERM` 该 PID → `systemctl --user reset-failed noctalia.service` → `start`。
- **sudo**：执行代理不得 sudo；主代理应用配置需用户提供密码或用户自己执行 `! sudo nixos-rebuild switch --flake .#nixos-btw`。不要把密码写进任何文件或记忆。
- **独显**：用户经常主动给 NVIDIA 独显断电，`nvidia-smi` 报 No devices 属正常；顶栏 GPU 项应隐藏而不是显示 “--”。
- **用户偏好**：不喜欢高饱和整块蓝底、紫粉配色、Tokyo Night；喜欢 One Dark、下划指示、现代简洁；界面不要太大（输出缩放 1.5）；复杂的 IDE 式布局（Islands、工具条）不受欢迎，倾向简洁的顶栏 + 按需侧栏。

## 11. 交接给另一个模型时

给新模型的第一条消息只需：

> 按 `docs/agent-workflow.md` 的流程工作：你是主代理，负责设计、写 brief、监控、审核、集成；实现交给执行代理。当前进度见 `.work/HANDOFF.md`。

`.work/HANDOFF.md` 必须写明：在跑的会话 ID 与工作树、未合并分支、每轮下一步、待用户决定的事项、已知限制。Codex 作为主代理时，实现可交给原生子代理或继续用 `codex exec` 后台执行代理（两者都按本文约束）。
