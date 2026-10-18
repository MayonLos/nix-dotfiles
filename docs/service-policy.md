# 后台服务策略

状态：2026-10-18，Den 声明已由用户 nr 应用，后续优化也获得应用授权；实现阶段历史证据见[Den 记录](den-execution.md)，当前运行交接见[应用记录](system-polish-execution.md)。服务可安装、可激活与实际正常运行仍须分别核实。

## 当前声明与生命周期

| 功能 | 声明和启动方 | 停止、恢复与数据边界 |
|---|---|---|
| 登录与会话 | host 明选 [login-screen](../aspects/interactive-session/greeter.nix)，greetd 启动 Mango。锁定 Mango C 实现先导入动态 DISPLAY/WAYLAND/cursor 环境并请求 `mango-session.target`；HM 非空 `autostart_sh = ":"` 是补充同步钩子，不是唯一启动路径。 | Mango 退出由其会话 target 路径结束；冷登录/退出时序未实机验证，不依赖 autostart 比 C 路径先运行。 |
| Noctalia | [HM renderer](../aspects/interactive-session/noctalia.nix) 启用官方 systemd unit，`PartOf`/`After`/`WantedBy` 均明确指向 Mango target；无直接 `noctalia &`。安全静态环境由同源白名单提供，`launch_apps_as_systemd_services = true`。 | `Restart=on-failure`、2 秒、60 秒内最多 3 次。应用独立 systemd 启动，不能因 shell 重启而退出；故障注入与真实应用存活未验证。启动前先做有限字段归属交接，旧 writer 活跃时拒绝修改。 |
| 输入法 | [Fcitx5/Rime](../aspects/interactive-session/input-method.nix) 的官方 HM daemon 定向绑定 Mango target。输入法环境仅共享明确的键，不复制全部 home vars。 | 用户词库、学习数据和应用状态保留。候选框缩放、QQ/微信、实际退出与恢复未验证。 |
| 剪贴板 | Noctalia 原生历史是唯一日用历史生产者，不声明 cliphist watcher；[clipboard bridge](../aspects/interactive-session/clipboard.nix) 只做 Wayland/X11 selection 桥接，Mango target 拉起。 | 桥接 `Restart=always`、2 秒、3 次/60 秒；一侧 watcher 退出则结束两侧并重启，读操作有超时。历史、旧数据库与 Secret Service 状态不清理。真实图片/文字双向复制及 Secret Service 解锁待验收。 |
| X11 DPI | [xrdb-merge](../aspects/interactive-session/xresources.nix) 随 Mango target 运行 oneshot，有限重试等待 Xwayland。 | 不替代客户端实际缩放检查；无常驻轮询进程。 |
| Portal / keyring / polkit | [交互宿主支持](../aspects/interactive-session/default.nix) 共享提供 portal backend、keyring/PAM 和系统 polkit；Noctalia 提供图形认证 agent。 | 这些是宿主共享能力，不是每账号私有的访问控制。每个 bus 名称只能有实际预期 backend；屏幕共享、解锁与单 agent 需实测。 |
| 音频 | [PipeWire/WirePlumber](../aspects/interactive-session/host/audio.nix) 是共享宿主支持，保留 ALSA/Pulse/JACK、echo cancellation 和现有通信兼容规则。全局 `sockets.target` wants 关闭，只有选中账号的 Mango target 请求 PipeWire sockets。 | 支持 socket 按需激活，音频进程继续遵循 user manager 生命周期，不随 Noctalia 重启。未选账号不会自动得到个人音频启动配置；共享系统能力仍可被显式请求。实际音频设备与休眠恢复待验收。 |
| 网络与设备 | NM/resolved、Clash、Bluetooth、Intel/NVIDIA、power profiles、thermald、upower、earlyoom 等由真实 laptop host 明确选择。Nix daemon 代理只在 laptop-network，不进入通用维护。 | 不按通用身份或平台隐式启用。休眠不主动关闭业务/VM/容器；无新增周期设备轮询或通用 sleep inhibitor。 |
| SSH | [closed-ssh-socket](../aspects/remote-access/host.nix) 保留 socket 激活，防火墙不放行，未新增授权 key。 | 这是笔记本现有策略，不能作为已可远程登录的服务器配置。真实机器须另行明确网络、key 与恢复入口。 |
| 本地容器 | [local-containers](../aspects/local-containers/default.nix) 与 container-client 分开。host 复用官方 rootless support，但关闭全局 daemon wants 和全局 socket 环境；所选 HM binding 提供完整 daemon unit 与 shell/environment.d 的 DOCKER_HOST。 | 仍为 user manager 的 `default.target` daemon，官方 `Restart=always`/2 秒和限制保留；不是 Docker socket 激活。未新增 linger，当前实机 Linger=no 的生命周期保持，最后注销后不能承诺容器继续。安装 CLI 不启 daemon。 |
| Docker prune | 只由 local-containers binding 声明每周、Persistent timer，拉起 oneshot `docker --host unix://%t/docker.sock system prune -f`。 | 保留现有调度和语义，不添加 `--volumes`，不在本轮执行 prune。仍会移除 Docker 判定为 unused 的对象；后续观察 timer、日志与范围，不把 prune 当数据迁移或备份。 |
| 本地虚拟机 | [local-virtual-machines](../aspects/local-virtual-machines/default.nix) 授予所选 binding 的 libvirtd/kvm，host 配置 QEMU KVM、runAsRoot=false、swtpm、SPICE USB。virt-manager 客户端可单选。 | `libvirtd.service` 的开机 wants 明确清空，保留 Unix sockets；旧实现同时有 multi-user wants，故本轮显式修正。`libvirt-guests` 保持关闭，不设置或改变 domain autostart。镜像、TPM 和 guest 生命周期属用户数据。 |
| AI / 应用 | [AI workbench](../aspects/ai-workbench/default.nix) 和其他应用 feature 安装 CLI/desktop entry；认证与可变设置留给应用。 | 不新增开机 daemon。工具启动后自身的按需子进程不等同 Nix 服务；模型、OAuth、Codex/OpenCode 配置与历史保留。 |
| 维护 | system-maintenance 提供 Nix optimise 和既有 NH 清理调度；真实 repo path 属于当前 host。 | 保留既有 generation 保留规则；本轮不手动 GC，不在回退验收前清理备份或构建产物。 |

## 环境、文件与授权

Noctalia/Mango 只消费 [白名单投影](../lib/session-environment.nix) 的安全静态值；动态 DISPLAY/WAYLAND 由 compositor 导入。不是所有 `home.sessionVariables` 都进入 user manager，更不将 secret 复制进去。Docker 的动态运行时 socket 值由所选账号 environment.d 提供，首次应用需完整重登录以刷新旧 manager。

[写入归属](config-ownership.md) 规定声明文件、应用 mutable 设置、历史/缓存/模型与 runtime secret 的边界。Noctalia sidecar 交接不覆盖整个 state；GTK/Qt/Firefox 模板、Kitty/Mango 单 renderer 及逐字段 patch 的实际 apply/undo 仍需应用后验证。用户组按 binding，host udev/portal/PAM 是共享支持；USB `uaccess` 按活动 seat，并不提供按 Den binding 的 USB 隔离。

## 迁移前只读快照

基线阶段重新检查了系统/user unit、进程元数据和 Linger；没有读取剪贴板、认证、模型或业务数据。发现仓库已移除的 llama-cpp 和两条 cliphist watcher 仍从旧持久用户 unit 运行，Noctalia 也有非新 unit 管理的实例。未停止它们、删除其文件或声称声明变化已经生效。应用阶段应先确认 writer/数据归属，再有序退出旧服务；Noctalia guard 继续拒绝活 writer。本轮已在核实进程身份后，只对旧 shell 通过 pidfd 发 SIGTERM，等其优雅退出并确认 writer scan 为空，再 reset-failed/start 新 unit；无需注销 Mango，不终止终端或业务任务。

先前只读查询 `qemu:///system` 与 `qemu:///session` 未发现 domain，这是当时快照；不推断后续创建的 guest。Docker/VM 卷和镜像没有复制、清理或修改。

## 验收与资源测量

根 checks 验证生产组合的宿主/账号选择、共享支持、移除最后 consumer、客户端不启 daemon、unit wants、组授权、配置 parser 和有限字段工具。构建不启动服务。ARM 只做无头组合求值，未做目标系统构建或运行；没有虚构服务器。

应用后按实际 generation 记录以下项目，未完成者不得标成通过：

1. 唯一 Noctalia writer、冷登录/退出的 Mango target 顺序、unit PartOf/After/WantedBy、manager 安全环境与 D-Bus 单 agent。
2. 旧 llama/cliphist 的有序停用与历史/模型保留；新服务故障恢复和已启动应用存活。
3. Noctalia 逐键备份及 GTK/Qt/Firefox apply/undo，Kitty/Mango 不被模板改写；IME、截图、剪贴板与屏幕共享。
4. Docker timer 仅预期用户运行、socket 环境正确、prune 范围；libvirt socket 连接、各 URI 的 domain XML/autostart 只读核对。
5. 音频/蓝牙/USB/外屏、greeter、游戏、休眠/唤醒和低电量 hook（放电跨越 5% 时 suspend）的真实行为。
6. 同负载前后测量 CPU、RSS、IO、进程数、重启间隔及电池，记录 commit/lock/generation、内核、接电/profile、显示器/网络、命令、采样窗口与波动。无同条件基线不归因于重构，不宣称性能或续航改善。

长期不可恢复任务可由用户选择 sleep inhibitor；配置不自动阻止休眠、杀游戏、暂停/关闭 VM 或容器。未来服务器另按[真实实例规划](server-plan.md)确定服务账号、端口、数据保护和部署。

源码依据为当前 `flake.lock` 的 Mango C/HM、Noctalia HM 和 stable nixpkgs 的 docker-rootless/libvirtd/pipewire 模块；本轮以实际锁定源码核实，不沿用旧注释推断启动行为。
