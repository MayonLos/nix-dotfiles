# 后台服务策略

状态：2026-10-19，Den 声明已由用户 nr 应用，后续优化也获得应用授权；实现阶段历史证据见[Den 记录](history/den-execution.md)，当前运行交接见[应用记录](history/system-polish-execution.md)与[系统界面记录](history/system-experience-execution.md)。服务可安装、可激活与实际正常运行仍须分别核实。

第八轮架构目录迁移未应用配置；全部 21 个 checks 与 system toplevel 已通过过滤源码快照构建，见[第八轮记录](history/architecture-v2-execution.md)。本页运行证据仍只适用于此前应用的 generation；新源码的实际服务状态须在应用后核对。

## 当前声明与生命周期

| 功能 | 声明和启动方 | 停止、恢复与数据边界 |
|---|---|---|
| 登录与会话 | host 明选 [login-screen](../aspects/desktop/greeter/greeter.nix)，Noctalia Greeter 的默认会话为 Mango，另可明确选择 dwm / Xorg。锁定 Mango C 实现先导入动态 DISPLAY/WAYLAND/cursor 环境并请求 `mango-session.target`；HM 非空 `autostart_sh = ":"` 是补充同步钩子，不是唯一启动路径。 | Mango 退出由其会话 target 路径结束。冷登录/退出时序仍需实机核验，不依赖 autostart 比 C 路径先运行。当前移除状态见[执行记录](history/hyprland-removal-execution.md)。 |
| Noctalia | [HM renderer](../aspects/desktop/mango-session/noctalia.nix) 启用官方 systemd unit，`PartOf`/`After`/`WantedBy` 均指向 Mango target；无直接 `noctalia &`。安全静态环境由同源白名单提供，`launch_apps_as_systemd_services = true`。 | `Restart=on-failure`、2 秒、60 秒内最多 3 次。应用独立 systemd 启动；本轮正常 shell 交接中受保护业务存活已核验，故障注入与会话退出仍未验证。启动前先做有限字段归属交接，旧 writer 活跃时拒绝修改。 |
| 输入法 | [Fcitx5/Rime](../aspects/desktop/session-support/input-method.nix) 的官方 HM daemon 绑定已选 Mango / Xorg targets。输入法环境仅共享明确的键，不复制全部 home vars。 | 用户词库、学习数据和应用状态保留。候选框缩放、QQ/微信、实际退出与恢复未验证。 |
| 剪贴板 | Mango 中 Noctalia 原生历史是唯一日用历史生产者，不声明 cliphist watcher；[clipboard bridge](../aspects/desktop/mango-session/clipboard.nix) 只做 Wayland/X11 selection 桥接，随 Mango target 拉起。 | 桥接 `Restart=always`、2 秒、3 次/60 秒；一侧 watcher 退出则结束两侧并重启，读操作有超时。历史、旧数据库与 Secret Service 状态不清理。真实图片/文字双向复制及 Secret Service 解锁待验收。 |
| X11 DPI | [xrdb-merge](../aspects/desktop/session-support/xresources.nix) 随选中的 Mango / Xorg target 运行 oneshot，有限重试等待 X server。 | 不替代客户端实际缩放检查；无常驻轮询进程。 |
| 可选 dwm / Xorg | `xorg-session.target` 仅由 supervisor 在 dwm 就绪后启动；Picom、Dunst、CopyQ、polkit、状态、壁纸、RandR watcher、idle 与 xss-lock 都具备 desktop/target guard。 | 不启动 Noctalia 或 Wayland clipboard bridge。Dunst D-Bus 激活同样受约束；Rofi 按需运行；xidlehook 以15/30/60分钟触发锁屏/熄屏/休眠，xss-lock独立保护睡眠锁屏；共享采用 X11 原生能力。实际构建/运行边界详见 [Xorg 记录](xorg-desktop-execution.md)。 |
| Portal / keyring / polkit | [交互宿主支持](../aspects/desktop/session-support/default.nix) 共享提供 GTK portal backend、keyring/PAM 和系统 polkit；Noctalia 提供图形认证 agent。 | 这些是宿主共享能力，不是每账号私有的访问控制。每个 bus 名称只能有实际预期 backend；屏幕共享、解锁与单 agent 需实测。 |
| 音频 | [PipeWire/WirePlumber](../aspects/desktop/session-support/host/audio.nix) 是共享宿主支持，保留 ALSA/Pulse/JACK 和现有通信兼容规则；不常驻 echo-cancel 模块（它常开内置麦并把默认输出拉进麦克风的 256 帧图，导致蓝牙 A2DP 持续丢包），回声消除由通话应用自带。WirePlumber 关闭蓝牙耳机自动切到 HFP：麦克风采集（如 pavucontrol 电平条）曾把 A2DP 切成 8/16 kHz 单声道并导致断连，耳机麦需手动选 HFP profile。全局 `sockets.target` wants 关闭，只有选中账号的桌面 targets 请求 PipeWire sockets。 | 支持 socket 按需激活，音频进程继续遵循 user manager 生命周期，不随 Noctalia 重启。未选账号不会自动得到个人音频启动配置；共享系统能力仍可被显式请求。实际音频设备与休眠恢复待验收。 |
| 网络与设备 | NM/resolved、Clash、Bluetooth、Intel/NVIDIA、power profiles、thermald、upower、earlyoom 等由真实 laptop host 明确选择。Nix daemon 不强制指向 Clash 本地端口；Clash 关闭时保留直接下载能力。 | 不按通用身份或平台隐式启用。休眠不主动关闭业务/VM/容器；无新增周期设备轮询或通用 sleep inhibitor。 |
| 内核与调度 | legion-laptop 选 stable 默认 LTS `linuxPackages`（当前声明锁定 6.18.59），NVIDIA stable（595.71.05）由同一 kernelPackages 提供，保留 open / PRIME offload。`scx.service` 随 `multi-user.target` 启动 `scx_lavd` 1.1.2，空参数保留按负载调整的默认 autopilot，不使用跟随电源 profile 的 `--autopower`。 | 服务以 `/sys/kernel/sched_ext` 为启动条件，失败自动重启，30 秒内最多 2 次；无需桌面会话提供。2026-10-24 18:11 实机启动已核对 `uname -r = 6.18.57`、NVIDIA 595.71.05、`scx.service` active、sched_ext `enabled` 且 ops 为 `lavd_1.1.2`，legion 模块已加载、Wi-Fi 已连接。后续启动和交互稳定性仍需持续观察；证据与回退见[第四轮记录](history/optimization-2026-10-24.md#第四轮lts-内核stable-nvidia-与-sched-ext)。 |
| SSH | [closed-ssh-socket](../aspects/network/remote-access/host.nix) 保留 socket 激活，仅绑定 `127.0.0.1:22` 与 `[::1]:22`，防火墙不放行，未新增授权 key。 | 这是笔记本现有策略，不能作为已可远程登录的服务器配置。真实机器须另行明确网络、key 与恢复入口。 |
| 本地容器 | [local-containers](../aspects/dev/containers/default.nix) 与 container-client 分开。host 复用官方 rootless support，但关闭全局 daemon wants 和全局 socket 环境；所选 HM binding 提供完整 daemon unit 与 shell/environment.d 的 DOCKER_HOST。 | 第45轮声明改为所选账号的 `docker.socket` → `docker-proxy.service` → 私有 socket 的 rootless daemon，daemon 不再有登录 wants，保留官方 `Restart=always`/2 秒和限制。默认不 idle stop；容器 restart policy 在 daemon 首次按需启动时恢复，而非登录立即恢复。未新增 linger，最后注销后不能承诺容器继续。该声明尚未应用。安装 CLI 不启 daemon。 |
| Docker prune | 只由 local-containers binding 声明每周、Persistent timer，拉起 oneshot `docker --host unix://%t/docker.sock builder prune -f --filter until=168h`。 | 2026-10-20 起自动清理限于一周未使用的构建缓存，停止容器、镜像与卷不属于该命令清理范围；保留原计时器名称和每周调度。没有手动执行 prune；清理不替代备份。 |
| 本地虚拟机 | [local-virtual-machines](../aspects/dev/virtual-machines/default.nix) 授予所选 binding 的 libvirtd/kvm，host 配置 QEMU KVM、runAsRoot=false、swtpm、SPICE USB。virt-manager 客户端可单选。 | `libvirtd.service` 的开机 wants 明确清空，保留 Unix sockets；旧实现同时有 multi-user wants，故本轮显式修正。`libvirt-guests` 保持关闭，不设置或改变 domain autostart。镜像、TPM 和 guest 生命周期属用户数据。 |
| AI / 应用 | [AI workbench](../aspects/dev/ai-agents/default.nix) 和其他应用 feature 安装 CLI/desktop entry；认证与可变设置留给应用。 | 不新增开机 daemon。工具启动后自身的按需子进程不等同 Nix 服务；模型、OAuth、Codex/OpenCode 配置与历史保留。 |
| 维护 | system-maintenance 提供 Nix optimise 和既有 NH 清理调度；真实 repo path 属于当前 host。 | 保留既有 generation 保留规则；本轮不手动 GC，不在回退验收前清理备份或构建产物。 |

## 环境、文件与授权

Noctalia/Mango 只消费 [白名单投影](../aspects/desktop/mango-session/session-environment.nix) 的安全静态值；动态 DISPLAY/WAYLAND 由 Mango 导入。AI workbench 将两个 ACP adapter 的静态可执行路径同源声明为 shell 与 systemd 会话变量，Mango/Noctalia 通过该白名单转交给桌面启动的编辑器。不是所有 `home.sessionVariables` 都进入 user manager，更不将 secret 复制进去。Docker 的动态运行时 socket 值由所选账号 environment.d 提供，首次应用需完整重登录以刷新旧 manager。

[写入归属](config-ownership.md) 规定声明文件、应用 mutable 设置、历史/缓存/模型与 runtime secret 的边界。Noctalia sidecar 交接不覆盖整个 state；GTK/Qt/Firefox 模板、Kitty/Mango 单 renderer 及逐字段 patch 的实际 apply/undo 仍需应用后验证。用户组按 binding，host udev/portal/PAM 是共享支持；USB `uaccess` 按活动 seat，并不提供按 Den binding 的 USB 隔离。

## 迁移前只读快照

基线阶段重新检查了系统/user unit、进程元数据和 Linger；没有读取剪贴板、认证、模型或业务数据。发现仓库已移除的 llama-cpp 和两条 cliphist watcher 仍从旧持久用户 unit 运行，Noctalia 也有非新 unit 管理的实例。未停止它们、删除其文件或声称声明变化已经生效。应用阶段应先确认 writer/数据归属，再有序退出旧服务；Noctalia guard 继续拒绝活 writer。本轮已在核实进程身份后，只对旧 shell 通过 pidfd 发 SIGTERM，等其优雅退出并确认 writer scan 为空，再 reset-failed/start 新 unit；无需注销 Mango，不终止终端或业务任务。

先前只读查询 `qemu:///system` 与 `qemu:///session` 未发现 domain，这是当时快照；不推断后续创建的 guest。Docker/VM 卷和镜像没有复制、清理或修改。

## 验收与资源测量

根 checks 验证生产组合的宿主/账号选择、共享支持、移除最后 consumer、客户端不启 daemon、unit wants、组授权、配置 parser 和有限字段工具。构建不启动服务。ARM 只做无头组合求值，未做目标系统构建或运行；没有虚构服务器。

应用后按实际 generation 记录以下项目，未完成者不得标成通过：

1. 唯一 Noctalia writer、Mango 冷登录/退出 target 顺序、退出后共享服务清理、unit PartOf/After/WantedBy、manager 安全环境与 D-Bus 单 agent。
2. 旧 llama/cliphist 的有序停用与历史/模型保留；新服务故障恢复和已启动应用存活。
3. Noctalia 逐键备份及 GTK/Qt/Firefox apply/undo，Kitty/Mango 不被模板改写；IME、截图、剪贴板与屏幕共享。
4. Docker timer 仅预期用户运行、socket 环境正确、prune 范围；libvirt socket 连接、各 URI 的 domain XML/autostart 只读核对。
5. 音频/蓝牙/USB/外屏、greeter、游戏、休眠/唤醒和低电量 hook（放电跨越 5% 时 suspend）的真实行为。
6. 同负载前后测量 CPU、RSS、IO、进程数、重启间隔及电池，记录 commit/lock/generation、内核、接电/profile、显示器/网络、命令、采样窗口与波动。无同条件基线不归因于重构，不宣称性能或续航改善。

长期不可恢复任务可由用户选择 sleep inhibitor；配置不自动阻止休眠、杀游戏、暂停/关闭 VM 或容器。未来服务器另按[真实实例规划](server-plan.md)确定服务账号、端口、数据保护和部署。

源码依据为当前 `flake.lock` 的 Mango C/HM、Noctalia HM 和 stable nixpkgs 的 docker-rootless/libvirtd/pipewire 模块；本轮以实际锁定源码核实，不沿用旧注释推断启动行为。

执行操作、回滚和当前重构的验证状态见[操作说明](operations.md)。本轮源码目录迁移尚未应用，不能用本页既有 generation 的观察代替新配置验收。

第 37 轮声明调整（尚未应用）：GTK 提供两个会话的 FileChooser/Settings，移除需要 Mutter 的 GNOME portal；gnome-keyring Secret 与 Mango wlr capture 保留。共享 session-support 合并显式 D-Bus 服务目录并保留标准 XDG 用户目录发现；Dunst 仍为 Xorg 专用，包内唯一规范服务名通过受 guard 的 systemd unit 激活。PipeWire 不再加载无人使用的 X11 bell 模块，常规音频与通知声音保留。蓝牙关闭未使用的实验性 LE Audio profile；经典 A2DP 保留，仍需应用后实测。

第 38 轮系统优化声明（尚未应用）：Legion 保留 earlyoom 的 RAM 5% / swap 10% 阈值，关闭没有监控 cgroup 的 systemd-oomd；保留 zstd / 50% RAM 的 zram 容量，设置 swappiness 100、page-cluster 0。该笔记本的 Nix 并行度改为 2 个构建、每个 8 个 worker；ext4 根挂载使用 noatime。维护显式保持 keep-outputs=false，删除上游已提供的重复 root trust/官方 cache key。SSH socket 改为仅 loopback；远程访问仍需明确授权与接线。生成配置和构建不能证明应用后的内存峰值、启动时间或功耗改善。

第38轮审计同时确认：Mango 下的 xrdb-merge 服务承担 Xwayland DPI/根光标设置，属于两个会话共用的 oneshot，不能按 Xorg 专属误删。Docker 继续保留官方 rootless 常驻 unit；锁定模块没有 socket，不能直接用 fd:// 绕过 RootlessKit 的文件描述符边界。NVIDIA persistence 保留原关机崩溃规避；未改 fine-grained PM、外屏、CUDA、游戏、电源 profile 或网络后端。

第45轮性能/游戏声明（尚未应用）：rootless Docker 使用 systemd-socket-proxyd 转发至私有 daemon socket，避免 RootlessKit 的 fd:// 边界；weekly builder prune 保留且可触发 daemon。GameMode 首/末客户端钩子保存并恢复 PPD 原 profile，CPU governor 仅由 PPD 管理（锁定 1.8.2 包补充 ignore 开关）；关闭 GPU 调频、split-lock 和 ioprio 改写，按需持有独立 logind idle inhibitor，gamemoded 退出时执行恢复；不阻止手动锁屏/显式休眠，也不重启 scx。Steam 不再全局 preload（该方式会使 steam-runtime lsof 崩溃）；每个游戏设置 `gamemoderun %command%`，helper blacklist 只处理显式包装链；Prism 在实际游戏启动边界包装 game-run。NVIDIA 模块加载与 persistence 关机规避保持。隔离测试不等同应用后冷登录、真实游戏与容器验证，细节见 [Gaming](../aspects/apps/gaming/README.md) 与 [Containers](../aspects/dev/containers/README.md)。


第47轮 TUI 声明（尚未应用）：自写程序集中在
[mayon-tui](../packages/mayon-tui/README.md)，不新增后台服务。Clash GUI 的 Nix
`autoStart` 显式关闭；serviceMode root helper 仍提供 TUN 权限，GUI 打开后请求启动
内核、退出或 SIGTERM 时由 Verge 2.4.7 清理系统代理/TUN/内核。GUI 自己既有的
mutable auto-launch 设置不在 Nix writer 范围，需实机在 Verge 设置中确认关闭。
TUI 的 `s` 复用 Noctalia 原生 app-launch 策略，`X` 只向本 UID、验证 executable
路径并固定 pidfd 的 GUI 发 SIGTERM。只验证过私有 mihomo 与编译替身，真实 GUI
启动、TUN/DNS 恢复仍待应用后验收。

Docker TUI 使用公开 `%t/docker.sock`，首次请求可能启动 daemon；确认停止时先取消
并等待自身所有 API 请求，再执行 user docker/docker-proxy stop，并暂停刷新直到
用户按 `s`。公开 socket 保留，下次连接仍可按需启动。端口 TUI 默认不探测尚未
启动的标准 Docker endpoint（即使 DOCKER_HOST 指向该端点，也需私有 daemon
socket 已存在）；`--docker-map` 是显式强制查询。隔离真实 rootless daemon 仍受
newuidmap 权限限制，Docker 交互证据来自私有 API fixture，不代表实机已运行。
