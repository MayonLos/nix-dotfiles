---
name: host-hardware
description: 修改或排查 nixos-btw 的内核/NVIDIA、硬件加速、Docker/libvirt、内存、网络代理和系统服务。
---

# 主机硬件与服务

所有路径相对仓库根目录。主机入口是 `hosts/nixos-btw/`；
硬件扫描文件不用于堆积日常配置，功能配置放 `modules/system/`。

## 按症状读取

| 任务 | 必读内容 |
|---|---|
| 内核、NVIDIA、PRIME、关机/挂起、视频解码 | [GPU 与内核](references/gpu-kernel.md) |
| Clash/TUN、DNS、nix 下载卡住、开放 SSH | [网络与代理](references/network.md) |

当前内核是 `pkgs.linuxPackages_zen`，驱动使用 unstable NVIDIA recipe 与系统内核组合。
旧文档的“必须 LTS”已被实际配置替代；不凭旧说明回退内核，也不只靠求值证明驱动能编译。

## 容器与虚拟机

- `modules/system/services/docker.nix`：rootless Docker，`setSocketVariable` 提供客户端 socket。
  不假设 `/var/run/docker.sock` 有 root daemon。
- 每周用户 timer 执行 `docker system prune -f`，会清理停止的容器、未用网络、
  dangling images 和构建缓存；排查数据消失时先核对清理策略，勿自行运行清理。
- `modules/system/virtualisation/libvirt.nix`：KVM、virt-manager、swtpm，用户属于 libvirtd/kvm。
  修改 VM 生命周期前看 `libvirt-guests` 的当前设置，不假设自动保存已启用。

## 内存、构建目录与清理

- `modules/system/services/oom.nix` 的 earlyoom 防止桌面内存耗尽卡死；不要作为冗余服务删除。
- `modules/system/core/boot.nix` 使用 zram 与 tmpfs `/tmp`。nix-daemon 的 TMPDIR 为 `/var/tmp`，
  避免大包构建挤爆内存；shell 的 TMPDIR 不能代替该 unit 配置。
- `modules/system/programs/nh.nix` 的 flake 路径是绝对路径，移动仓库需更新。
  weekly clean 保留最近 5 代及 14 天内版本；不把清理当审核步骤。

## 设备访问

`modules/system/hardware/debug-probes.nix` 安装 openocd/stlink 的 udev 规则，调试探针通过
`uaccess` 给登录会话授权；不补造 plugdev。串口 ttyUSB/ttyACM 使用 dialout，
用户组在 `modules/system/user/mayon.nix`。工具链由 `dev-toolchain` 管。

音频、蓝牙、固件分别在 `modules/system/hardware/{audio,bluetooth,firmware}.nix`；
电源相关服务在 `modules/system/services/systemd.nix`。先确认运行中的具体 unit，再调整模块。

## 应用打包边界

Flatpak 曾因运行时占用被移除；优先仓库已有 Nix 包、nix-ld 或 FHS wrapper。
用户明确需要 Flatpak 时再重新评估，不把历史取舍写成用户不能改变的限制。
QQ/WeChat 的协议与依赖包装见 `desktop-apps`；游戏 GPU 选择见 `gaming-stack`。

## 验证

模块改动先求值，驱动 / 内核变动须构建 toplevel；切换或重启需要任务本身包含应用。
关机、挂起、硬件解码是运行时结论，报告实际测了哪些，不能由构建成功代替。
