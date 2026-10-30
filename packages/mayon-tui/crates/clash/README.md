# Clash TUI

`clashtui-mayon` 提供七页：概览、代理、订阅、连接、规则、日志、工具/设置。
Super+Shift+C 打开。第49轮试用版保留 Verge，新增独立 native 后端；
不自动启动内核，`s` 手动开、`X` 确认关。退出 TUI 本身保留运行的服务。

## 后端与归属

`~/.config/mayon-tui/clash.toml`（尊重 XDG_CONFIG_HOME）是用户维护的只读偏好：

```toml
backend = "auto"         # auto / native / verge
test_url = "https://www.gstatic.com/generate_204"
timeout_ms = 5000        # 100–30000
concurrency = 4          # 1–32，b 批量测速
default_sort = "default" # default / delay / name
default_page = 1        # 1–7
```

auto 在**启动 TUI 时**探测 Verge Unix socket：可连则使用 Verge，否则 native。
native controller 为 `/run/mayon-clash/mihomo.sock`；Verge 为
`$XDG_RUNTIME_DIR/clash-verge-rev/verge-mihomo.sock`。状态行标记后端。
`--backend` 覆盖偏好，`--socket` 显式指定私有 controller，绝不回退 TCP。

native 服务由 laptop-network 声明，以绑定用户运行锁定 mihomo 1.19.24，
只具备 CAP_NET_ADMIN/BIND_SERVICE；polkit 只授权该用户 start/stop/restart
`mayon-clash.service`。没有 boot wants/timer/自动重启，不设置系统代理或
nix-daemon 代理环境。TUN 开时接管流量，关服务后直连；显式代理默认
127.0.0.1:7897。allow-lan 默认 false，显式开启会监听所有地址，但不放行防火墙。
停止时服务先 PATCH 运行中 TUN 为 false，再由 systemd 结束内核，规避锁定版本
在初始化完成前尚未注册 SIGTERM 清理处理的竞态；持久 TUN 设置保留。
启动前拒绝可连的同 UID Verge socket；切回 Verge 前须先 X 关闭 native。

## native 数据和配置

TUI 是 `~/.local/share/mayon-clash/` 的唯一配置 writer，HM 不管理这些文件：

| 路径 | 归属和权限 |
| --- | --- |
| 数据根与 subscriptions/ | 当前用户，0700 |
| subscriptions.toml | URL、ID、当前项、标题、用量、更新时间、间隔与节点数；0600 |
| subscriptions/ID.yaml | 完整订阅缓存，0600 |
| settings.toml | TUN、mode、IPv6、allow-lan、log-level、mixed-port、允许的基础覆盖；0600 |
| config.yaml / config.previous.yaml | 已校验 runtime / 上一份配置；0600 |
| writer.lock / 临时文件 | 多进程写入锁 / 同目录原子替换；0600 |
| GeoIP.dat / GeoSite.dat / Country.mmdb | 初次从 Nix store 复制，随后可更新，0600 |
| cache.db、providers 等 | mihomo 运行时拥有，服务 umask 0077；保留所选节点 |
| /run/mayon-clash/ | systemd 管理，0700，属绑定用户；停止后移除 |

mihomo 主动 chmod socket 为 0666；0700 runtime 目录阻止其他用户连接。
不启 TCP controller，不设 secret。Nix store 没有订阅 URL 或正文。

首次写入用 yq 精确读取 Verge `clash-verge.yaml` 的
`tun/dns/sniffer/profile/ipv6/mode/log-level`，没有读其他 runtime 字段或 secret。
若文件不存在则使用内建 mixed TUN/fake-ip DNS 默认值；读取失败时报错，不静默
替换。sniffer 缺省按关闭处理，TUN device 固定为 `mayon-clash`。用户后续设置
优先于基础值，DNS IPv6 随 IPv6 设置同步。第一次导入/添加后即保存基础值，后续
不再读取 Verge runtime。非本机首次使用者应在工具页核对 TUN/DNS 需求。

保留订阅 proxies/proxy-groups/rules/rule-providers/proxy-providers；覆盖本地
监听、controller、TUN、DNS、sniffer、profile.store-selected、IPv6、模式和日志。
移除订阅带来的额外监听/TCP controller/secret/UI/认证/iptables/ntp，避免引入
非预期入口。Geo 用 `-d` 下固定文件名，`geodata-mode=true`；文件可写，工具页
更新不写 Nix store。provider 路径仍受 mihomo safe-path 检查。

每次操作持有 flock；临时文件 0600 → `mihomo -t`（45s 上限，输出不回显）→
fsync → rename。校验子进程用 seccomp 拒绝 IPv4/IPv6 socket，保证离线导入不因
mihomo 的缺失 Geo 自动下载而联网；缺少规则所需数据时校验失败并保留原文件。
运行中 `PUT /configs?force=true`，再读取实际 TUN/模式/监听端口，避免把内核的
HTTP 204 误当成监听成功；失败恢复旧文件并重载、核对旧配置，
回滚失败明确提示。跨多个文件不是系统级原子事务，进程崩溃/掉电仍需检查索引与
runtime；每个单文件替换原子，正常错误有回滚。正常退出 TUI 会等待已发起的
native 事务结束，粘贴仅作为输入文本处理，不触发全局快捷键。

## 订阅与设置

- `i` 添加：粘贴 URL（只显示 scheme://host/…），Tab 可选名称。
  名称默认 profile-title（含 base64）、content-disposition，再用主机名。
- `u/f` 更新所选，`U` 更新全部，Enter 切换；`n` 重命名、`e` 编辑 URL。
  下载采用 Verge 2.4.7 的 `clash-verge/v2.4.7` User-Agent，记录用量、到期、
  profile-update-interval（小时，默认24h）。先直连，失败且内核运行时经当前
  本机 mixed-port 重试；最多32 MiB，25s 请求上限，跟随最多5次重定向。
- TUI 打开且内核运行时每分钟检查超期项，后台串行更新，不阻塞绘制；没有服务外
  常驻 updater 或 timer。直连意味着不使用 HTTP 代理，仍可能经过已开启的 TUN。
- `I` 从 Verge profiles.yaml 的 remote 项和缓存离线导入，不联网；原当前项标记
  `Verge 原当前` 并设为当前，重复 URL 跳过。URL 不输出、不写日志、不放截图。
  **不执行 merge/script/rules/proxies/groups 增强**，导入前确认、导入后提示。
  缓存缺失或校验失败整次拒绝；不写 Verge 文件。重新导入同 URL 不覆盖已有缓存。
- `d` 确认删除非当前项；当前项需先切换。用量条、7天内到期高亮、配置内节点数、
  上次更新时间显示于订阅页；外部 provider 内的节点不算进“配置内”数量。
- `7` 工具/设置：j/k、Enter 切换 TUN、模式、IPv6、allow-lan、日志级别；mixed-port
  用弹窗编辑。离线同样保存，有当前订阅时重新校验，运行中立即热加载。
- `s` 没订阅时引导去订阅页；有订阅则生成配置、请求服务、等 socket/API。
  后台更新中确认 X 会排队关闭，等当前写入结束即停止，无需重复按 X。
  失败读取 Result/ExecMainStatus 和最后20条 journal，仅分类成中文原因，原日志
  不显示（可含节点/URL）。`X` 停服务，等 socket 消失；不会启动或停止 Verge。

## 其余页面与 Verge 兼容

`1–7` 切页，j/k/方向键、g/G、PgUp/PgDn、鼠标点击/滚轮，`/` 过滤，`?` 按页帮助。
代理页：Tab/h/l 面板，Enter 选节点，t 单测、T 组测、b 并发批测、Esc 取消，
S 默认/延迟/名称，H 隐藏超时，c 跳当前，v 详情，p 节点源。
支持中英/拼音首字母模糊过滤，按 grapheme 截断，延迟色与 Verge 一致。
Selector/URLTest/Fallback 可选，组测速恢复自动策略；LoadBalance 不能选单节点。

连接页：S 排序，Enter 详情，x/d/D 确认关闭单个/过滤快照/全部；Unix WebSocket
每秒更新。规则页：p 规则源，u 更新，Enter 命中详情；累计计数缺省时显示当前
连接匹配数量。日志页：L 最低级别、空格暂停、G 追随、最多2000条，仅内存，
隐藏链接/常见凭据。工具前三项确认后清 fake-ip/DNS 或更新 Geo，需内核运行。
概览累计是内核本次运行流量，订阅用量来自响应头，二者不同。

Verge 后端保持 r48：profiles 只读，每2秒刷新；TUN/系统代理只显示，o 打开
Verge；订阅更新/切换回退到 GUI，URL-only deep link 导入，命名导入回退。
Verge 2.4.7 自身会记录导入链接；TUI 提示这一限制。s 复用 Noctalia app-launch，
X 只对同 UID、固定 pidfd 且 executable 匹配的 GUI 发 SIGTERM，由它清理。
`--no-verge` 禁止这些外部 Verge 操作；不禁止 native 试验替身。

## 非交互入口与隔离

CLI 使用与 TUI 相同的事务；URL 从 stdin 读取，避免进入 argv：

```sh
# 在用户自己的终端输入；本例不会把真实 URL 放进 shell history
read -r -s subscription
printf '%s' "$subscription" | clashtui-mayon profile add '我的订阅'
unset subscription
clashtui-mayon profile list                 # ID + 名称，不输出 URL
clashtui-mayon profile update ID            # 或 all
clashtui-mayon profile use ID
clashtui-mayon profile rename ID '新名称'
# profile url ID 从 stdin 接收新 URL，下载校验成功后才替换
clashtui-mayon profile delete ID --yes      # 当前项不可删除
clashtui-mayon profile import-verge
clashtui-mayon profile generate
clashtui-mayon settings tun false
clashtui-mayon service start                # generate + systemctl start
clashtui-mayon service stop
```

CLI 公共参数：`--data-dir`、`--socket`、`--profiles`（Verge 索引）、`--mihomo`、
`--systemctl`。TUI 另支持 `--backend/--config/--test-url/--usage-proxy`。
开发必须从 env -i 启动，独立 HOME/XDG/D-Bus/headless Sway；真实 Kitty 宽窗与
90列截图。显式 private socket、测试 systemctl/journalctl 和纯用户 mihomo，关闭
TUN；不能连接真实 controller、系统服务或用户 Wayland。配对 Verge 替身参数保留。

`backend.rs` 选后端，`native.rs` 管订阅/配置/事务，`cli.rs` 暴露脚本入口；
api/profiles/search/settings/app/ui 保持各自模型、传输、过滤、状态和绘制职责。
单测覆盖合并、头解析/脱敏、导入 fixture、探测、并发锁、校验失败与热加载回滚；
workspace clippy/test/release 和 NixOS VM check 登记于仓库 checks。
移除程序/feature 不清理 native 或 Verge 数据，下一轮确认满意后才删除 Verge 代码。
