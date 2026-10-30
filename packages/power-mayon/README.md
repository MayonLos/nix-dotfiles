# power-mayon

Legion 电池与性能模式工具，`power-mayon` / `power-mayon tui` 打开 TUI。
Rust 前端复用 `mayon-ui` 的 One Dark palette、细边框、淡选中行、蓝色标记、数字分页和帮助；
Python 标准库后端处理 sysfs、/proc、文件锁与受限命令。程序不写 sysfs、不执行 shell、不含 root helper。

## 使用

```sh
power-mayon status --json             # 只读、无历史写入、无 NVIDIA 驱动查询
power-mayon status --json --sample    # 250 ms CPU/RAPL/进程采样，不写历史
power-mayon status --json --nvidia    # 显式查询当前active的NVIDIA；仍有唤醒竞态
power-mayon mode power-saver          # balanced / performance
power-mayon conservation on           # off；通过 legion-conservation
power-mayon auto configure --ac balanced --battery power-saver --gamemode keep
power-mayon auto enable               # 只保存opt-in；下次30秒timer/tick应用
power-mayon auto tick
power-mayon auto disable              # 保留当前模式，不恢复为其他模式
power-mayon watch                     # 显式前台采样与规则循环；Ctrl-C结束
```

需要 PPD 提供的 `powerprofilesctl`；`mode` 只接受三个字面值并检查 PPD 实际可用列表。
PPD D-Bus/polkit 负责权限；公开包导出 `profilePolicy` 字符串，由Legion host采用，
只授予所选 `power-mayon` 组 `org.freedesktop.UPower.PowerProfiles.switch-profile`，
使无活动session归属的user timer也可切换三个profile，不授权hold/configure-action或任意命令。
该组需应用配置并刷新登录，构建不授予当前用户新权限。养护复用 Legion 已有组、udev
单属性权限和 `legion-conservation on|off`（保留原 `status|toggle`），由固件决定保护区间，
不谎报可编程百分比。缺失、多节点或非法值拒绝修改。

键位：`1–4` / `Tab` 切页；`j/k`、方向键、滚轮移动；概览 `Enter` 选模式，
`s/b/p` 一键省电/均衡/性能；`c` 确认养护；`g` 确认启用 NVIDIA 查询，再按关闭；
进程 `/` 过滤；规则 `a/d/f` 循环 AC/电池/GameMode配置，`e` 确认开启或关闭自动；
`?` 帮助，`Esc` 取消，`q` 退出。鼠标可点击页签和模式行。

## 采样与限制

- 电池支持 `energy_*`，以及 `charge_* × voltage_now` 回退（后者 Wh 为估算）；
  百分比、健康、循环、充/放电功率、余量/充满时间分别保留 `null` 表示不可读。
  预计时间只在充放电、功率超过0.1 W时给出，低功率或满电没有可靠预计时长。
- CPU 显示全机 busy%、cpu0 瞬时频率/governor、可读 RAPL 包能量差分。
  仅加顶层 package zones，处理一次计数器回绕，不重复计算 core/uncore。
  普通用户常无 RAPL 权限；不放宽内核权限，不伪造瓦数。
- 进程按 `/proc/PID/stat` CPU ticks / 全CPU ticks（含 idle）分摊 package W，
  这是功耗估算，非单进程电表；不含进程 GPU/IO，不分摊空闲功耗。
  没有 RAPL 时只给 CPU 占比；显示最多40个活跃CPU进程（dGPU设备打开者另列）。PID 与 starttime 配对，避免 PID 复用错算。
- 默认只读 PCI `runtime_status` / `power_state`，Intel 可读频率/busy；
  不调用 `nvidia-smi`，不读取 NVIDIA hwmon。
  显式 `--nvidia` / `g` 只对检查时 active 且非 D3 的设备查询功耗、温度、利用率；
  检查与驱动查询之间仍有竞态，可能唤醒 GPU，不承诺无扰动。
  休眠、断电或消失设备跳过；没有 GPU 时 devices 可为空。
- dGPU 进程来自当前用户可读的 `/proc/*/fd` 对 NVIDIA/DRM 设备的引用，
  同时覆盖可见图形和计算客户端；其他用户/受保护 fd 不可见。设备打开者可能完全空闲，
  不证明 GPU 正在运行，不给这些进程伪造 GPU 瓦数。
- 温度与风扇仅显示可读 hwmon 属性，零值按传感器原值展示；无属性就不显示。
- 历史每30秒至多一条、最多720条、单文件最多512 KiB。TUI 打开或显式 `watch` 时采集；
  单次 `status` 不写文件，规则 timer 不采集。曲线为电池充/放电功率幅值；AC 下不等于墙上功耗。
  硬件读数受采样间隔、传感器/驱动语义影响，不能据此声称续航或性能改善。

## 自动规则与 writer

默认 `enabled=false`；未显式开启不改现有 profile。所选 Legion 用户安装30秒 user timer，
无配置时通过 ConditionPathExists 跳过；配置存在但关闭时 tick 直接返回。
开启后AC/电池规则持续生效，TUI退出不影响；`mode` 在自动启用时拒绝，先关闭自动再手选。
不接管 scx_lavd、TLP（本机未启用）、governor、风扇或GPU电源。

**集成前必须由桌面 owner 删除 Noctalia 原 battery_charging / battery_discharging profile hooks。**
本分支不改桌面文件；旧钩子当前仍存在，会与开启后的新规则争写。低电量休眠 hook保留。

GameMode 已有 first/last-client 保存/恢复 performance 事务。
本工具复用 `$XDG_RUNTIME_DIR/gaming-mode/lock`，持锁时复查 state.json。
`gamemode=keep` 默认让出；显式选定其他模式后，仅当日志 `active is True` 且保存的profile为合法枚举才应用规则，
从不改钩子保存的原profile。坏日志、缺字段、active=false（恢复待处理）都保守让出。
手动mode仍拒绝任何存在的日志。GameMode开始时钩子先切performance，自定义规则在下一轮
最多30秒后生效；结束时仍由原钩子恢复，后续tick再应用AC/电池规则。
关闭自动或改回keep不会立即还原已覆盖的GameMode模式，需等待钩子结束恢复或显式手动选择。
控制子命令各1.5秒超时、同锁内最多四次调用（6秒），避免长期阻塞钩子的10秒锁等待。
只有所选账号协同，不能约束其他账号或外部PPD控制方。
开启/关闭自动不会还原旧profile；这是持续规则，不是临时hold。

## 状态/配置与移除

`$XDG_CONFIG_HOME/power-mayon/config.json`（默认 `~/.config`）：

```json
{"enabled":false,"ac":"balanced","battery":"power-saver","gamemode":"keep"}
```

`$XDG_STATE_HOME/power-mayon/{history.json,lock}`（默认 `~/.local/state`）。
工具目录0700、写入文件0600；配置和历史通过锁、fsync、临时文件+rename写入，拒绝符号链接。
仅存时间戳、功率、电源状态、profile；不持久化进程名/命令行。
`status` 仅读配置/历史，不创建目录。桌面owner只读JSON，不成为第二个配置writer。
移除包/feature撤回二进制、timer声明；配置、历史、用户数据和固件/当前profile保持。
重建安装不会切换模式或写养护值；运行时权限和timer需应用后验收。

## JSON v1（Noctalia）

稳定字段（数值可能为 `null`，不能用0代替缺失）：

| 字段 | 含义 |
|---|---|
| `schema_version`, `timestamp` | 版本1、Unix秒 |
| `ac_online` | true/false/null |
| `profile.current`, `profile.available`, `profile.error` | 当前PPD字符串/可用字符串数组/错误 |
| `batteries[]` | name、percent、status、health_percent、cycles、power_w、energy_wh、full_wh、design_wh、energy_source、voltage_v、time_to_empty_s、time_to_full_s |
| `conservation.available/enabled/kind/threshold_percent` | 可用性、bool/null、firmware-conservation、null（无任意阈值） |
| `cpu.busy_percent/package_power_w/power_source/governor/frequency_mhz` | CPU采样；默认status未采样部分为null |
| `gpu.devices[]` | pci、vendor、runtime_status、power_state、power_w、temperature_c、utilization_percent；Intel可带frequency_mhz |
| `gpu.processes[]` | pid、name、devices；读取范围见process_scope |
| `temperatures[]`, `fans[]` | name+celsius / name+rpm |
| `processes[]` | pid、name、cpu_percent、estimated_power_w（仅采样时） |
| `estimate_method` | 估算范围说明 |
| `automatic.enabled/ac/battery/gamemode/gamemode_pending/gamemode_policy` | opt-in规则与GameMode协同 |
| `history[]` | timestamp、battery_w、cpu_w、ac_online、profile |

Noctalia“性能模式”行读 `profile.current/available`；点击调用固定 `power-mayon mode <枚举>`，
自动开启或GameMode期间禁用手动项。“电池”行逐个读 `batteries[]` 和 conservation。
切换失败保留错误提示并重新读取状态。默认不传 --nvidia，不能因刷新面板而唤醒独显。

## 验证和参考

`test_backend.py` 用临时mock sysfs、/proc、命令替身测试；`vm.nix` 在独立NixOS VM中
以无特权账号测试同包后端的控制路径和生产CLI只读JSON；使用真实polkit检查组内switch-profile授权、非成员与其他action拒绝。VM不证明真实PPD硬件切换、EC或显卡。
Cargo check/test/clippy/rustfmt和Python测试纳入包check。
测试接口 `POWER_MAYON_SYSFS/PROCFS` 只改变读取路径；控制仍固定调用现有CLI，不带提权。

参考 [mayon-tui](../mayon-tui/README.md) 的UI与键位、
[PowerTOP](https://github.com/fenrus75/powertop) 的估算展示思路（未复用其调参/校准操作）、
[Linux powercap](https://cdn.kernel.org/doc/html/latest/power/powercap/powercap.html) 能量计量接口、
[PPD](https://salsa.debian.org/freedesktop-team/power-profiles-daemon) 的profile CLI，
以及本仓库 [Gaming](../../aspects/apps/gaming/README.md) 的事务式GameMode策略。
