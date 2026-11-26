# 额外系统工具

为选中的 Home Manager 用户提供一组硬件诊断、存储维护与网络诊断工具。除包安装外，它只做两类
明确接线：Newsboat 的只读新闻源和 `trip` 的 `CAP_NET_RAW` wrapper。

## 输入

没有 schema、quirk 或主机侧输入。通过 `personal-desktop` bundle 或直接
`includes = [ den.aspects.extra-tools ]` 选择；包来自锁定 nixpkgs 的全局 `pkgs` 实例。

## 输出

| 包 | 用途 |
|---|---|
| `lm_sensors` | `sensors` 读取温度、电压和风扇；不运行 `sensors-detect`，不加载内核模块。 |
| `s-tui` | 终端 CPU 频率、温度、功耗与利用率监视。 |
| `nvme-cli` | NVMe 设备查询与维护。 |
| `smartmontools` | `smartctl` SMART 查询；不启用 `smartd`。 |
| `nvd` | 比较 Nix store 中两代 closure 的差异。 |
| `bluetui` | 终端蓝牙管理 TUI；BlueZ 服务和权限由系统现有配置提供。 |
| `gdu` | 终端磁盘占用分析。 |
| `gparted` | 图形分区编辑器；分区写入仍由 polkit 认证和运行中的文件系统状态约束。 |
| `newsboat` | 终端 RSS/Atom 阅读器；HM 生成 5 个公开新闻源（NixOS Discourse、LWN、Phoronix、少数派、IT之家）。 |
| `trippy` | `trip` 网络路径追踪；`security.wrappers` 提供 `cap_net_raw+ep`。 |
| `bind.dnsutils` | `dig`、`nslookup`、`host`；与 `pkgs.dnsutils` 是同一 derivation。 |

具体版本由 `flake.lock` 锁定的 nixpkgs 决定。

## 边界

安装软件不等于启用或配置功能：

- `newsboat` 的新闻源是公开默认值，可在 `default.nix` 修改；没有自动刷新 daemon。
- `trippy` 通过 wrapper 获得 raw socket 能力；wrapper 只在 `/run/wrappers/bin` 生效。
- `lm_sensors` 没有 `sensors-detect` 配置，`smartmontools` 没有 `smartd`，`bluetui` 没有新增
  蓝牙服务。
- `gparted` 只是安装 GUI；不预设分区布局，也不写 `fstab`，授权由会话 polkit agent 处理。

## 拥有文件与状态

本 feature 拥有 `default.nix`、本 README、HM 生成的 `~/.newsboat/urls` 与
`~/.config/newsboat/config`，以及系统侧的 `trip` wrapper。它不写 activation 脚本、systemd unit
或 MIME 项。

运行期状态归各应用和用户所有，例如 Newsboat 的已读/缓存数据库；这些都不由本 feature 声明、
写入或迁移。

## 移除后状态

从 bundle 或绑定中移除 `extra-tools`，并删除 `aspects/default.nix` 中的登记后，下一次 Home
Manager 激活会撤销这些包的安装。已有的新闻源、应用配置和缓存保留在用户目录中，不由本 feature
清理；由于没有系统服务或系统级声明，移除不涉及 systemd 状态。
