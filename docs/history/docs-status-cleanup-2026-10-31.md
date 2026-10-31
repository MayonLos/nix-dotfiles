# 顶层文档状态清理（2026-10-31）

按 `docs/README.md` 第 4 条，把顶层文档里随时间失效的状态移到这里。下面是被替换或移走的原文，只对应写下时的提交，不代表现状。声明类事实（内存参数、portal、Docker socket 等）在清理时对照源码核实，保留在原文档中。

## service-policy.md

状态：2026-10-19，Den 声明已由用户 nr 应用，后续优化也获得应用授权；实现阶段历史证据见[Den 记录](history/den-execution.md)，当前运行交接见[应用记录](history/system-polish-execution.md)与[系统界面记录](history/system-experience-execution.md)。服务可安装、可激活与实际正常运行仍须分别核实。

第八轮架构目录迁移未应用配置；全部 21 个 checks 与 system toplevel 已通过过滤源码快照构建，见[第八轮记录](history/architecture-v2-execution.md)。本页运行证据仍只适用于此前应用的 generation；新源码的实际服务状态须在应用后核对。

## 迁移前只读快照

基线阶段重新检查了系统/user unit、进程元数据和 Linger；没有读取剪贴板、认证、模型或业务数据。发现仓库已移除的 llama-cpp 和两条 cliphist watcher 仍从旧持久用户 unit 运行，Noctalia 也有非新 unit 管理的实例。未停止它们、删除其文件或声称声明变化已经生效。应用阶段应先确认 writer/数据归属，再有序退出旧服务；Noctalia guard 继续拒绝活 writer。本轮已在核实进程身份后，只对旧 shell 通过 pidfd 发 SIGTERM，等其优雅退出并确认 writer scan 为空，再 reset-failed/start 新 unit；无需注销 Mango，不终止终端或业务任务。

先前只读查询 `qemu:///system` 与 `qemu:///session` 未发现 domain，这是当时快照；不推断后续创建的 guest。Docker/VM 卷和镜像没有复制、清理或修改。

本轮正常 shell 交接中

第45轮声明改为所选账号的 `docker.socket`

该声明尚未应用。安装 CLI

旧实现同时有 multi-user wants，故本轮显式修正。

本轮不手动 GC，不在回退验收前清理备份或构建产物。

；本轮以实际锁定源码核实，

执行操作、回滚和当前重构的验证状态见[操作说明](operations.md)。本轮源码目录迁移尚未应用，不能用本页既有 generation 的观察代替新配置验收。

第 37 轮声明调整（尚未应用）：GTK

经典 A2DP 保留，仍需应用后实测。

第 38 轮系统优化声明（尚未应用）：Legion

第38轮审计同时确认：Mango

第45轮性能/游戏声明（尚未应用）：rootless

## config-ownership.md

本轮仅声明，不在用户 home 创建/应用；默认图由

自定义值。本轮未应用，锁屏和 greeter 实际显示待验。 |

本轮部署/验收见

本次 Den 改造可验证源码组合、生成配置、构建的 unit 和隔离 fixture；这些只能证明声明/构建层行为。早期实现任务未应用系统；用户随后自行应用，历次授权与操作只对对应历史记录有效。本轮第五轮没有应用配置。

第 37 轮声明调整（尚未应用）：FileManager1

## neovim.md

# Neovim AI 重构（2026-10-24）

本轮以 `nvim-ai` / `cdbe549` 隔离 worktree 为基线，完整替换键位与 AI 工作流。
配置尚未应用，不执行 sudo、nixos-rebuild 或 Git commit/push；合并冲突可由主代理暂存以标记解决。此前构建路径、性能样本、
检查结果和实机待验项记录于[本轮历史](history/nvim-ai-2026-10-24.md)。

本轮未修改超出写入范围的 tmux 配置，主代理需合入历史文件中的 tmux 片段。

实际 health、构建命令与限制见本轮历史。

- 微信输入法问题待解决：主代理实测 XCB/Fcitx wrapper 无效，本轮撤销为直接安装 wechat；
  问题挂起，不改用户数据。上一轮 wrapper 构建记录保留作历史，不能视为实机成功。

## xorg.md

见[本轮执行记录](history/xorg-r24

不代表本轮实现或应用状态。

本轮要求的隔离显示为

[第二十四轮记录]

## xorg-visual.md

2026-10-19。以 `f4686d6` 干净工作树为本轮基线。用户指出

## 证据与应用边界

本轮只读观察：用户当前已在 generation 395 的真实 DWM/X11 会话，
`xorg-session.target` active，`mango-session.target` inactive。运行系统为
`/nix/store/r8ly0x2p8qdbqxxjm14glpd90zw39b11-nixos-system-nixos-btw-26.05.20261012.7993f34`。
这证明此前登录修正已在本次运行中可用，不表示本轮视觉改动已应用。

当前实际窗口清单只有 Kitty，`WM_CLASS="kitty", "kitty"`，浮动标记为 0。
QQ、会议与 IDE 的规则检查使用合成 X11 客户端，不冒充真实应用运行证据；
它们后续出现特殊工具窗口时，应读取实际 class/type/transient，再补精确规则。
不通过猜中文标题把整类程序改成浮动。

设计与构建阶段仅在自有 Xvfb 中运行检查，当时不执行 switch、boot、注销、重启或真实锁屏，
不终止现有任务；用户数据、凭据、历史和模型不变。

## 本轮验证结果

- `xorg-session-runtime` 构建通过：十项 supervisor 生命周期检查、QQ 后端与 argv、
  生产 dwm 的单/双窗口布局、比例浮窗、完整浮动/全屏几何恢复、父子窗口、Qt 工具规则、
  pager 跨 tag 激活。QQ/会议/IDE 主窗口规则为明确的合成 class fixture。
- 生产 j4/dmenu 中文入口与 Exec 参数保真、控制菜单 Escape、未知输入不执行通过。
  第二个 420×260 / 144 DPI Xvfb 验证菜单边界、居中、滚动到末项与取消退出。
  此固定场景不是完整多屏或多 DPI 验收。
- Picom 配置在测试专用 XRender 后端启动，Dunst 实际发送通知，日志无错误。
  生产 GLX 和 NVIDIA/Intel 驱动行为没有借此冒充完成。
- 实际 Astra 逐张查看整桌、启动器、小屏菜单；另建 1600×1000 / 144 DPI Xvfb 运行
  生产锁屏 wrapper，检查时钟、中文、日期与认证环。映射窗口后模拟睡眠延迟 FD 释放通过；
  未输入密码，不证明实机 PAM 解锁或休眠恢复。
- 独立 reviewer 对配方、窗口状态、FLOATPOS 语义、菜单几何、测试边界与服务归属复核。
  构建过程中先后捕获了错误的 floatpos 居中写法及 dmenu 参数解析的宏重复求值，
  均修正后才取得下列最终通过结果；失败迭代不作为通过证据。
- `nix flake check --no-build --no-write-lock-file` 全部求值通过；treefmt、
  `desktop-composition`、完整主机 toplevel 构建通过。输入锁未修改。

窗口实测：1600×1000 显示中，单平铺窗口 x=21、y=78、客户区 1554×897；
Pavucontrol class fixture x=280、y=198、客户区 1036×656；边框计入后按工作区居中。
这些尺寸是隔离输出的测量，不是实际 Pavucontrol 的内容最小尺寸验收。

最终系统：`/nix/store/3y8abkr7hkq0x6gshvaisxh7nan1w6hj-nixos-system-nixos-btw-26.05.20261012.7993f34`。
运行检查：`/nix/store/jwymwzbpm8v8lhlp42krsy5b58cb09p8-xorg-session-runtime`，含四张预览、
`geometry.json`、小屏结果及各进程日志。锁屏预览 `/tmp/dwm-lock-preview-lormuwh7/lock-preview.png`，
仅为临时验收产物，不纳入配置或用户数据。构建日志为 `/tmp/codex-dwm-v2-runtime.log`、
`/tmp/codex-dwm-v2-system.log`。

实现本地提交 `e456740`（视觉与窗口规则）、`0a044d4`（菜单与行为检查）；本轮不 push。
应用新结果后需要重新进入 DWM 才会启动新的 dwm 二进制；本轮没有更换当前运行的 WM。

## 用户授权后的系统应用

2026-10-19 12:41:46，用户明确要求“切换好”。先执行已构建结果的 `dry-activate`，
计划只重启 `home-manager-mayon.service`，不会重启 greetd 或结束桌面；随后执行
`sudo nixos-rebuild switch --flake .#nixos-btw --no-write-lock-file --max-jobs 1 --cores 2`，返回 0。
系统 profile 为 generation 396，`/run/current-system` 指向上述最终系统；
上一代 generation 395 保留。应用日志 `/tmp/codex-dwm-v2-switch.log`。

实际检查：Xorg target、Picom、Dunst、状态、壁纸与空闲锁屏服务 active，Mango target inactive；
用户管理器没有 failed units。Picom 在生产 GLX 配置下启动且没有新增错误日志，
不把短时服务启动扩大为完整 GPU/性能验收。Dunst 重载时尝试 Wayland 后出现警告并回退 X11，
服务仍 active/running、Result=success，`dunstctl` 查询正常；此记录不宣称生产日志完全无警告。

切换前后 greetd 的两个进程、DWM 与两个 Codex 的 PID/启动时间均未改变，没有注销或重启。
现有 DWM PID 2373 仍运行旧包 `ccdpq46w06gpwd46whkalsgjc8n9c42c`；已激活的会话脚本指向
新包 `jb17b1bkgjrirz9jmc30927i0ql2cdba`。菜单、通知、合成与壁纸配置已加载，
新 DWM 的栏、间距和窗口规则需要用户之后重新登录 **DWM** 才生效；不能标为已热加载。

## obsidian.md

2026-10-29 的重构方案在 `vault-stage` 实现，并在独立 HOME、D-Bus 和无头 sway
中的 `vault-shot` 验证。它是待主代理同步的配置，不代表真实笔记库已经迁移。

隔离应用会使用官方应用更新包，
最终实际应用版本及截图、控制台记录以本轮交接报告为准，不能由安装器版本推断。

不能视作本轮隔离视觉验证

；本轮按用户要求删除过时

本轮只构建仓库配置，并在隔离 Obsidian 验证笔记库副本；没有系统激活，
没有访问真实笔记库，也没有向 Claudian 发送消息。每轮实际测试与未实现项见交接报告。

## agent-workflow.md

在本轮成果基础上继续

## dsh.md

见[本轮记录](history/optimization

## apps.md

用户已确认常用，本轮不删。
