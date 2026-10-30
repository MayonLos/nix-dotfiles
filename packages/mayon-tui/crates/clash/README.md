# Clash TUI

`clashtui-mayon` 是已有 Verge / mihomo 的日常控制面板：概览、代理、订阅、连接、规则、日志、工具。
默认从概览回答“开着吗、走哪条链路、还剩多少”。首次使用按 `?`，帮助随页面给出概念与操作。
Den `clash-tui` aspect 由 laptop-network 登记，只安装公开 `pkgs.mayonTui.clash`。
包工厂、测试、palette 与另外两个工具共用 [Rust workspace](../../README.md)。

## 输入、输出与归属

- Unix controller 默认为 `$XDG_RUNTIME_DIR/clash-verge-rev/verge-mihomo.sock`，不回退 TCP，不读取密钥。
- 订阅元数据默认为 `$HOME/.local/share/io.github.clash-verge-rev.clash-verge-rev/profiles.yaml`。
  仅使用现有只读解析路径，在启动、每两秒和返回订阅页时重读 remote/local 项；URL 不显示、不记录。
  不读取配置中指向的订阅文件或订阅正文。节点数只在 provider 名能对应订阅 UID/名称时显示，否则明确未知。
- `/configs`、`/proxies`、`/version` 每两秒刷新；规则和 providers 每 30 秒或 `r` 刷新。
  `/traffic` 为每秒 HTTP JSON 行流；连接使用 Unix socket WebSocket，每秒快照。
  内存为内核快照的连接缓冲占用，累计流量为本次内核进程累计，不是订阅账单或 TUI 启动后累计。
  规则模式没有单一出口，概览显示参考组，实际链路在连接详情；global 模式从 GLOBAL 逐级展开。
- 系统代理只读查询 `gsettings get org.gnome.system.proxy mode`，不可用则显示未知；这不保证每个应用都遵守该设置。
  TUN 只读 `/configs`。**两个开关均由 Verge 管理**，TUI 只提供 `o` 打开设置，绝不 PATCH TUN。
- 日志在首次打开日志页后订阅 `/logs?level=debug`，最多 2000 条，仅存内存；隐藏 URL 与常见凭据赋值。
  暂停会丢弃新日志。流断开会重连，连接速率与流量状态明确标注未知/断开。
- 可选配置是用户自己维护的 `$XDG_CONFIG_HOME/mayon-tui/clash.toml`（默认 `~/.config/...`），TUI 只读，HM 不管理。

输出是终端画面、用户触发的 API 操作、经启动器交给 Verge 的导入请求和经身份校验的 GUI 退出请求。
用量刷新经显式代理 HEAD→GET 仅读取 `subscription-userinfo` 响应头，不消费正文、不跟随重定向、不回退直连、不写回 YAML。
没有新增服务或状态 writer。移除 feature 仅卸载程序，保留配置、订阅、凭据与所有应用数据。

## 使用与键位

```sh
clashtui-mayon
clashtui-mayon --help
# 全部使用合成数据和私有服务；禁止开发测试连接用户 controller。
clashtui-mayon --socket /private/runtime/mihomo.sock \
  --profiles /private/profiles.yaml --test-url http://127.0.0.1:32110/generate_204 \
  --usage-proxy http://127.0.0.1:32100 --no-verge
```

| 页面 / 范围 | 键与行为 |
| --- | --- |
| 所有页面 | `1–7` 切页；`j/k` / 方向键；`g/G`；PageUp/PageDown；`/` 过滤，Enter 接受，Esc 清除；`?` 按页帮助；`q` 退出 |
| 生命周期 | `s` 离线启动；`X` 确认退出 Verge；`m` rule/global/direct；`o` 打开 Verge 设置 |
| 代理（2） | Tab、h/l 切面板；Enter 选节点；`v` 完整名称/类型说明；`S` 默认/延迟/名称排序；`H` 隐藏超时；`c` 跳当前 |
| 测速 | `t` 单节点；`T` 内核组测速；`b` 对过滤列表按配置并发测试；Esc 取消本地队列/忽略过期结果 |
| 节点源 | `p` 进入/返回；`t` provider 健康检查；`u` provider 更新；Enter 详情 |
| 订阅（3） | `i` 导入，Tab 切隐藏 URL/名称；`f` 用量响应头；`u` 更新 / Enter 切换经 Verge 回退 |
| 连接（4） | `S` 速率/总量/时长/主机排序；Enter 完整详情；`x` 单个、`d` 过滤结果快照、`D` 所有连接，均需确认 |
| 规则（5） | `/` 类型/内容/策略过滤；Enter 完整规则和命中；`p` 规则源；`u` 更新所选源 |
| 日志（6） | `L` 最低级别；空格暂停；`/` 搜索；`G` 追随尾部 |
| 工具（7） | Enter 确认清 fake-ip / DNS 缓存或更新 GeoIP/GeoSite |
| 鼠标 | 点击页签/行选择，双击行执行 Enter，滚轮移动；弹窗底部左右按钮确认/取消，导入字段可点击；帮助滚轮切页 |

代理过滤支持中文、英文和拼音首字母，允许模糊子序列（如 `xg` 匹配香港）。默认节点顺序保留配置顺序。
延迟配色按 Verge 2.4.7 `src/services/delay.ts::formatDelayColor`：`<250ms` 绿、`250–399ms` 蓝、
`>=400ms` 黄，达到测试超时或 10000ms 红；零/失败红，未测 `--`。
Selector、URLTest 和 Fallback 支持选择；后两者临时指定后，`T` 会清除强制选择并恢复自动策略。
LoadBalance 按连接分配，不能指定单一节点。Relay 在 mihomo 1.19.24 已移除，兼容 fixture 仍覆盖其显示。

## 可选配置

```toml
# ~/.config/mayon-tui/clash.toml （无需创建，不存在时用以下默认值）
test_url = "https://www.gstatic.com/generate_204"
timeout_ms = 5000       # 100–30000
concurrency = 4         # 1–32，仅控制 b 的客户端并发
default_sort = "default" # default / delay / name
default_page = 1         # 1 概览至 7 工具
```

`--config PATH` 指定其他文件，`--test-url` 可覆盖测试目标。格式或范围错误用中文报错，不输出输入内容。
组测速的并发由 mihomo `GroupBase.URLTest` 管理，接口没有并发参数；provider 健康检查使用 provider 自己的 URL/超时。
URLTest/Fallback 的组测 URL 也以组配置为准。取消请求不能保证撤回已到达内核的测试。
Geo 更新走 `POST /configs/geo`（等待上限 180s），Nix store 中的资源可能只读，此时明确显示失败，不改包或权限。

## Verge 2.4.7 边界与启动

依据锁定 nixpkgs：Verge 2.4.7，`verge-mihomo` 链接同一 nixpkgs 的 mihomo 1.19.24。
API 以该版本 `hub/route/{server,proxies,groups,provider,connections,rules,cache,configs}.go` 为准。
参考 [MetaCubeXD](https://github.com/MetaCubeX/metacubexd)、[zashboard](https://github.com/Zephyruso/zashboard)
的概览、筛选、provider/连接管理，以及 [JohanChane/clashtui](https://github.com/JohanChane/clashtui) 的终端导航；
生命周期和订阅写入保持本仓库 Verge 的归属边界。

- URL-only 导入用 `clash://install-config?url=<encoded>` 交给已运行 Verge。
  `utils/server.rs` singleton 只有 scheme/visible/pac 路由；Tauri `update_profile` / `patch_profiles_config` 属内部 IPC，无安全外部订阅更新/切换入口。
- 名称编码仍有上游缺陷（server 未将整个 link 编码，scheme 提取 url 后全部后缀），命名导入改为说明后打开 Verge。
  回退明确说明会打开窗口；用户完成后返回，TUI 每两秒只读重载。请求发出不代表导入成功。
- Verge 自己会将完整导入链接写日志（`utils/resolve/scheme.rs:15`），导入弹窗提示此事实；TUI 不记录 URL。
- `s` 保留 `noctalia msg app-launch <desktop>` 原生 AppProvider，继承其 app.slice / activation 策略；不复制或输出环境。
  可通过 `MAYON_CLASH_DESKTOP` 指定 desktop 文件。
  **静默启动已由 Verge 支持**：设置中的 `enable_silent_start` 控制 `utils/resolve/mod.rs::init_window` 的窗口显示。
  没有一次性 CLI 参数或可安全调用的外部设置接口；先在 Verge 开启该设置，之后 `s` 可按它的设置启动。
  TUI 不改用户设置，也不通过隐藏窗口命令干扰用户会话。
- 启动显示“已请求 → 等待 helper/socket → API 就绪”；无法从公开 API 单独证明 helper 健康，30s 超时会说明等待阶段。
- `X` 通过 pidfd 固定并校验同 UID、Nix store Verge GUI 可执行路径后发 SIGTERM，由 Verge 清理 TUN、系统代理、内核。
  不信号匹配 service/mihomo，不使用 pkill。`--no-verge` 禁止全部外部启动/停止。
  隔离验证使用成对、绝对路径 `--test-verge-executable` / `--test-launcher`，精确匹配编译替身。

Nix `autoStart=false` 只关闭 Nix 自启动项；用户既有 Verge auto-launch 设置仍需在 GUI 自行确认。
构建不应用配置，真实 helper/TUN/DNS/系统代理清理与静默启动须主代理实机核对。

## 维护与验证

`api.rs` 管类型、Unix HTTP/WebSocket 与固定中文错误；`profiles.rs` 管只读元数据/用量；
`settings.rs` 管可选配置；`search.rs` 管拼音与日志脱敏；`app.rs` 管状态和有界后台任务；`ui.rs` 仅绘制可见行。
共享 `mayon-ui` 按 grapheme cluster 截断，保留旗帜/组合 emoji；footer 只保留完整键动作并追加 `? 更多`。
每次数据/输入变化才重绘，缓存节点检索键；日志最多 2000 条，更新队列最多 128 条，避免忙流无限增长。

工作区 `cargo test --workspace --locked`、`cargo clippy --workspace --all-targets --locked -- -D warnings`、
`cargo fmt --all --check` 与三个 release 构建纳入既有 `checks.mayon-tui`。
合成 controller 回放、360 节点 / 1200 连接绘制、排序/拼音、宽字符/emoji、用量、路由方法、Unix WebSocket、确认取消均有测试。
交互与截图必须用私有 mihomo、独立 HOME/XDG/D-Bus、headless Sway 和真实 Kitty；不得对用户内核测试写操作。
