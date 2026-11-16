# 额外系统工具

为选中的 Home Manager 用户安装一组硬件诊断、存储维护、网络诊断与个人数据工具。这个 feature
只负责安装：不启用服务、不生成配置、不创建或迁移任何用户数据。

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
| `argyllcms` | 显示器色彩校准工具；不配置 colord、udev 或校准流程。 |
| `bluetui` | 终端蓝牙管理 TUI；BlueZ 服务和权限由系统现有配置提供。 |
| `gdu` | 终端磁盘占用分析。 |
| `newsboat` | 终端 RSS/Atom 阅读器；不生成 `~/.newsboat/urls`，不配置新闻源。 |
| `trippy` | `trip` 网络路径追踪；不处理 raw socket 权限。 |
| `bind.dnsutils` | `dig`、`nslookup`、`host`；与 `pkgs.dnsutils` 是同一 derivation。 |
| `restic` | 备份客户端；不启用服务或定时器，不创建仓库，不配置密码。 |
| `keepassxc` | 密码库 GUI 与 `keepassxc-cli`；不创建或配置密码库。 |

具体版本由 `flake.lock` 锁定的 nixpkgs 决定。

## 边界

安装软件不等于启用或配置功能：

- `restic` 只提供命令行客户端。没有 restic 服务、定时备份、仓库初始化、密码文件或环境变量。
- `keepassxc` 只提供程序。没有密码库、自动启动、浏览器集成或系统密钥环配置。
- `newsboat` 只提供阅读器。没有新闻源、`urls` 文件或定时刷新配置。
- `trippy` 的 raw socket 权限没有处理；普通用户能否直接运行取决于当前系统的
  capability/setuid 配置，本 feature 不添加此类授权。
- 其余工具同样只有安装声明：`lm_sensors` 没有探测配置，`smartmontools` 没有 `smartd`，
  `argyllcms` 没有色彩管理接线，`bluetui` 没有新增蓝牙服务或权限。

## 拥有文件与状态

本 feature 拥有的文件只有 `default.nix` 和 `README.md`。它不写 activation 脚本、systemd
unit、udev 规则或 MIME 项，也不创建配置文件。

运行期状态归各应用和用户所有，例如 Newsboat 的 `~/.newsboat/`、KeePassXC 的
`~/.config/keepassxc/` 与密码库文件、Restic 的仓库与 cache；这些都不由本 feature 声明、写入
或迁移。

## 移除后状态

从 bundle 或绑定中移除 `extra-tools`，并删除 `aspects/default.nix` 中的登记后，下一次 Home
Manager 激活会撤销这些包的安装。已有的新闻源、密码库、备份仓库、应用配置和缓存保留在用户
目录中，不由本 feature 清理；由于没有系统服务或系统级声明，移除不涉及 systemd 状态。
