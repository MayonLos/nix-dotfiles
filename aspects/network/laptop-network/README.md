# Laptop network

NetworkManager、IPv6、resolved、防火墙和两套手动 Clash 入口。`default.nix`
登记 `laptop-network`、`network-manager-user` 与 `clash-tui`；不新增 aspect。
`clash-tui` 的 Den 用户绑定以 `user.name` 选择 native 服务 owner，home/group
从 NixOS `users.users` 取得，不闭包捕获真实主机事实。只支持一个服务 owner。

Verge 2.4.7 保留，`serviceMode=true`、`tunMode=false`、`autoStart=false` 均不改变。
`tunMode` 只给 GUI capability，serviceMode helper 才提供 TUN 权限。用户既有
Verge auto-launch 是应用设置，需在 GUI 自行确认关闭。两套内核不得同时运行。

`native-clash.nix` 声明 `services.mayon-clash.user` 选项与系统
`mayon-clash.service`：没有 wantedBy、timer、socket activation 或自动重启；
`After/Wants=network-online.target`。手动启动不依赖桌面存活，退出 TUI 不停服务。
绑定用户仅能免密码 start/stop/restart 此单元，其他 systemd 操作没有额外授权。
使用锁定 `pkgs.mihomo` 1.19.24，capability 仅 NET_ADMIN/BIND_SERVICE。
上游 tunMode 的 PrivateDevices/PrivateUsers 放宽保留；controller 另需 AF_UNIX。
ProtectHome=read-only，数据目录是唯一额外 ReadWritePaths；RuntimeDirectory
由 systemd 单独管理。配置不存在、校验失败或该 UID 的 Verge socket 可连时
preflight 拒绝启动，只输出固定中文诊断，不回显配置或内核校验输出。

`~/.local/share/mayon-clash/` 由 TUI 初始化，属绑定用户，0700；索引、订阅、
设置与配置 0600。Nix 不包含订阅内容/URL。TUI 首次写入时用 yq 只选取 Verge
runtime 的 tun/dns/sniffer/profile/ipv6/mode/log-level 作为基础设置；没有读取
其他 runtime 字段。完整 remote 缓存导入是用户主动按 `I` 后的独立操作，
不执行 Verge 增强项。数据与移除后的保留边界见
[Clash README](../../../packages/mayon-tui/crates/clash/README.md)。

GeoIP.dat、GeoSite.dat、Country.mmdb 缺失时从锁定的 v2ray-geoip、
v2ray-domain-list-community、dbip-country-lite **复制**，随后属于用户运行时数据，
工具页 Geo 更新可覆盖。`geodata-mode=true` 使用 GeoIP.dat；mihomo 的 `-d`
决定 Geo/cache 路径，没有虚构 geodata-path YAML 选项。TUI 包 wrapper 给出 seed
源，服务 preflight 同样可 seed。socket 在 `/run/mayon-clash/mihomo.sock`，
父目录 0700/该用户；mihomo 1.19.24 主动 chmod socket 0666，访问隔离依赖父目录。
只监听 Unix controller，没有 TCP controller 或 secret；mixed-port 默认
127.0.0.1:7897。allow-lan 是用户可显式修改的设置，不自动放行防火墙。

不设置系统代理、不向 nix-daemon 添加代理环境。native 开启 TUN 时接管网络，
停止后回到直连；resolved 保留默认 stub listener。防火墙信任 native
`mayon-clash` 与 Verge `Meta`/`Mihomo` 接口。polkit 只允许该服务单元把 TUN 注册为
resolved 的默认 DNS 链路（dns-servers/domains/default-route）；resolved 的上游查询绑定物理
网卡，不注册就绕过 dns-hijack。真实 TUN/休眠恢复需在应用后验收。

本目录所有 Nix 文件私有，`checks.nix` 是显式公开测试钩子，登记于
`nix/checks.nix`：`laptop-network` 验证生产声明，`mayon-clash-vm` 在 2048 MiB VM
内检查 inactive、polkit、合成 HTTP 订阅、TUN 流量/API、socket 隔离、stop 后路由
恢复、Verge socket 冲突。程序与 preflight 源码统一在 `packages/mayon-tui/`，服务仅调用公开 clash 输出的
`bin/mayon-clash-preflight`，不跨目录引用包内私有源码。

移除 feature 只撤回声明与包；不会删除 NetworkManager profiles、Verge 数据、
native 订阅/设置/缓存、凭据或历史。移除前应手动停止 native 服务。

锁定 1.19.24 的 `main.go` 在 `hub.Parse`（含 TUN 构造、provider 初始化）结束后
才注册退出信号，接口刚出现即 SIGTERM 可能残留策略规则。服务 ExecStop 因此先
向自己的 Unix API PATCH `tun.enable=false`，经内核 tunMux 等待构造并清理后再
由 systemd 结束进程；不改持久 TUN 设置、不清理别的服务或接口。VM 重复三次
“接口出现即停止”，并比较停止前后路由与策略规则；只忽略 DHCP/IPv6 过期时钟。
