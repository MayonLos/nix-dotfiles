# 配置审核与 DSH 命令接线

2026-10-20。用户要求接好 DSH 命令行，并完整审核配置、给出后续建议。开始时工作树已有 Neovim、Noctalia、项目工作台和容器维护等改动；当前运行系统已包含此前优化。不回滚这些改动、不更新输入锁、不删除应用状态，不把审核解释为重写全部功能。

## 确认的发现与处理

| 发现 | 证据与影响 | 本次处理 |
|---|---|---|
| DSH 后端已安装，但终端缺少 `dsh` 入口 | `aspects/ai-workbench/ai-agents.nix` 原来只安装 `dsh-desktop`；桌面用绝对路径调用 CLI，shell 的 `command -v dsh` 无结果。阻止脚本直接调用已有 headless 功能。 | 安装轻量命令 wrapper，复用同一 patched runtime；默认使用桌面 Harness home，尊重有效的显式 `DSH_HOME`，并将空串/纯空白规范化。 |
| 本地手工 DSH wrapper 遮蔽新入口 | 应用后 `command -v dsh` 优先命中 `~/.local/bin/dsh`，该三行脚本硬编码当前 store 版本，未跟随声明式升级。 | 核验脚本结构和唯一目标后备份移出 PATH；新 shell 已命中 Home Manager 的 `dsh`。备份见下方记录。 |
| QQ 版本对比注释过时 | `aspects/communication/im.nix` 对 QQ unstable 的描述为 3.2.32，锁定源实际求值为 3.2.34。包选择本身正确。 | 删除易过期的版本号对比，保留 stable/unstable 取舍原因；没有变更安装包。 |
| tmuxp 软件用途说明过时 | `docs/application-review.md` 原来只记 Noctalia 消费者；`aspects/project-workbench/default.nix:15` 生成布局，`runner.py:105` 已通过 tmuxp 创建或复用 workspace。 | 更新消费者、布局及持久会话的责任说明。 |

DSH 的 profile 是另一项必须解释的边界：共用 home 不意味着模型设置自动同步。只读核验本机现有 Web/headless profile 均选中 Go 的 `deepseek-v4.1-flash`，provider 凭据引用相同；此次未手工改写模型 patch、凭据、登录或会话历史。用法见[DSH 说明](../dsh.md)。

本次覆盖内未确认其他需要立即修改的运行缺陷。没有据此保证全部硬件、GUI 或未来输入升级都无问题。

## 审核覆盖与证据

| 范围 | 核验内容 |
|---|---|
| `flake.nix`、`nix/`、`inventory/`、`bundles/`、`lib/` | 显式 aspect 登记、唯一真实 host、Den 组合、stable/unstable 接线、固定输入与 follows 边界。 |
| `aspects/system/` 与桌面相关 aspects | sops 运行时文件、服务 target 归属、Mango/Xorg 互斥、portal/audio、输入法、Noctalia、共享外观及其 checks。运行时秘密只核验元数据，不输出内容。 |
| 项目、语言、编辑器、容器与用户工作流 | 项目路径/参数验证、direnv 信任、tmuxp 会话复用、语言贡献与 Neovim wrapper、AI 命令、rootless Docker 缓存清理边界；Firefox、通信、文档、文件管理、媒体、游戏、嵌入式、VM 与默认工具入口。Firefox 真实 profile 位于 XDG 路径，已只读核验目录发现机制，没有读取账号或登录内容。 |
| 文档与运行态 | 当前操作说明、数据/配置归属；系统和用户 failed units、Home Manager 状态、已安装命令及隔离启动。 |

Luna 分别只读检查系统/桌面和项目/编辑器工作流；独立 reviewer 复核 DSH 接线与跨组件结论。按当前源码、锁定源码和实际行为取证，未把历史审核当作当前通过记录。

补充隔离行为实验：在临时 HOME/XDG、私有 tmux socket 和最小 Zsh direnv hook 下，先启动已有 tmux server，再通过 tmuxp 打开与真实配置同结构的项目工作区。编辑器和空 shell pane 均收到项目 PATH、`VIRTUAL_ENV` 与自定义环境标记。未接触用户 tmux server、真实项目或个人 Zsh rc；测试 server 已清理。现有生产 runner 不需要因此修改，但建议固化该回归场景。

## 后续方向

按价值优先，建议从界面重做转向可靠性和可恢复性：

1. **备份与恢复演练。** 当前已有配置交接备份和 Nix generations，但这不能替代项目、AI 会话、模型元数据、容器卷与 VM 的数据备份。先确定异机目的地、加密与保留策略，再用一份临时恢复样本验收；没有目的地时不部署空任务。仓库未声明完整数据备份的决定见[优化记录](optimization-2026-10-20.md)。
2. **统一 AI 路由的归属。** 明确 Go/DeepSeek 的 provider、model、端点由哪一层维护，凭据留在运行时；为 Web/headless/编辑器分别提供无密钥的可用性诊断。当前 profiles 独立是上游设计，不建议静默覆盖 GUI 设置或自动复制整份配置。
3. **补充真实交互回归。** 将已有 tmux server 与 Zsh direnv hook、DSH 默认/显式 home、编辑器窄窗口等场景纳入隔离检查；保留现有文件保护与会话测试。已有全套 checks 先稳定运行，不以增加插件数量代替验收。
4. **按实际需求增加多屏能力。** `aspects/interactive-session/host/portal.nix:38` 当前明确假设单屏，固定捕获 `eDP-1` 并禁用 chooser。接扩展屏后再增加输出选择与真实屏幕共享验收，目前不把它当成单屏缺陷。
5. **性能优化先测量。** 记录冷启动、空闲资源、语言服务器首响应和恢复时间，再挑出实际瓶颈。Neovim 当前 warm 启动样本约 75ms，没有依据继续以大规模重构追求未测量的加速。

不建议此时再更换桌面框架、引入 Neovim 发行版或扩充重叠 AI 客户端。现有职责边界与检查体系已清楚，后续改动应对应明确需求与可重现问题。

## 验证与应用

- `nix flake check --no-write-lock-file --max-jobs 1 --cores 2` 返回 0，包含检查求值和构建；已通过的缓存产物被复用，其余检查完成构建。
- 主机 toplevel 构建通过，`sudo nixos-rebuild switch --flake .#nixos-btw --no-write-lock-file --max-jobs 1 --cores 2` 返回 0；`/run/current-system` 为 `/nix/store/4m46391v3lhppb8h7ikp14jwrl5pkjiv-nixos-system-nixos-btw-26.05.20261012.7993f34`，与目标产物一致。
- Home Manager 为 active / Result=success / ExecMainStatus=0；系统与用户 failed units 均为空。切换前后的 39/39 个已记录 Mango、Noctalia、终端、Java、Codex 相关进程 PID 与内核 starttime 保持一致，没有注销、重启机器或关闭用户项目。
- 构建的真实 wrapper 在隔离 HOME/XDG 中分别测试未设置、空串、空白与含空格的显式 `DSH_HOME`；每项都能建立预期 headless profile、通过 `--help`，没有建立 legacy `~/.dsh`。
- 新登录 shell 的 `command -v dsh` 为 `/etc/profiles/per-user/mayon/bin/dsh`，版本 0.2.0-rc.2，`dsh headless --help` 通过；实际组合配置核验 Go provider/model 正确。没有发真实模型请求，不把该结果写成服务端端到端成功。
- 旧手工 wrapper 备份于 `~/.local/state/nix-dotfiles/ownership-backups/dsh-command-20261020-cwf8f7eh/dsh`；目录 `0700`、文件 `0600`。仅迁移该已识别脚本，用户数据保留。
- `git diff --check`、变更文档的本地链接核验通过；最终文档的 treefmt 检查通过。没有提交或推送。

审核不主动触发 Docker 清理、Nix GC、休眠、真实项目构建或付费模型请求；没有逐个启动全部 GUI、测试多屏/休眠/会议共享，不能由构建成功推断这些实机行为。
