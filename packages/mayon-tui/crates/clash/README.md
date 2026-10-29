# Clash TUI

`clashtui-mayon` 是 Rust + ratatui 原型，通过本机 Unix socket 控制已有的 mihomo，读取 Clash Verge Rev 订阅元数据。名字明确区分上游 Clash TUI 项目，不占用含义模糊的 `cl`。通过 Noctalia 原生启动器手动打开 Verge；确认退出时向经过 UID/可执行路径校验的 GUI 发 SIGTERM，由 Verge 清理内核、TUN 和系统代理。

## 输入与输出契约

选择 Den aspect `clash-tui`（由 laptop-network 注册）只安装公开 `pkgs.mayonTui.clash` 输出。源码属于统一工作区；palette 固定来源为仓库公开 appearance。没有新增 schema、持久配置或用户状态。包工厂是工作区 `default.nix`，不再提供 feature 私有包入口。

运行时输入：

- 默认 socket：`$XDG_RUNTIME_DIR/clash-verge-rev/verge-mihomo.sock`。只走 Unix，不退回 TCP controller；不读取 Verge `config.yaml` 或 `secret`。若 socket 返回未授权，只显示操作失败，不尝试寻找密钥。
- 默认订阅文件：`$HOME/.local/share/io.github.clash-verge-rev.clash-verge-rev/profiles.yaml`。启动时、打开订阅页或按 `r` 时只读；只显示 `remote`、`local`，过滤 merge/script 辅助项。
- `/proxies`、`/configs`、`/version`、`/connections` 快照每两秒更新；`/traffic` 为持续 HTTP JSON 行流，连接中断会自动重连。状态栏明确显示 offline，流量失联显示 `--`，不伪造零流量。
- 刷新用量使用当前内核 `/configs` 的 mixed-port，经显式 HTTP 代理访问订阅 URL；可用 `--usage-proxy` 指定 HTTP/SOCKS 代理。没有端口就停止，不回退直连。HEAD 无响应头时尝试 GET，只读响应头，不读取或保存订阅正文；禁用重定向，防止凭据被静默送到别的主机。

输出为终端画面和用户明确触发的内核请求（选择节点、切换模式、测速、关闭连接）。本 feature 不拥有任何持久配置、缓存、订阅、日志或用户状态文件；用量刷新只保存在进程内存。取消测速会停止本地队列并忽略过期结果，已经送达内核的最多四个请求仍可能执行到其 5 秒超时（mihomo 的测速 handler 使用独立后台 context）。移除 feature 只卸载入口，保留 Verge 和所有应用数据。节点/模式修改由 mihomo/Verge 的已有策略决定是否持久化。

颜色由 Nix 从实体 palette 生成编译期常量。直接运行 Cargo 时，共享 `ui/build.rs` 读取仓库公开的 `aspects/appearance/appearance/onedark.nix`，没有第二套硬编码配色。字体由宿主 Kitty 提供，推荐系统现用的 Maple Mono NF CN。中文截断使用 `unicode-width`，选中行为淡底加蓝色左边线。

## 使用

```sh
clashtui-mayon
clashtui-mayon --help
# 隔离验证：必须显式指定私有 socket、合成文件和本地测速目标。
clashtui-mayon --socket /private/runtime/mihomo.sock \
  --profiles /private/profiles.yaml --test-url http://127.0.0.1:31910/generate_204 \
  --usage-proxy http://127.0.0.1:31900 --no-verge
```

| 键 | 行为 |
| --- | --- |
| `1` / `2` / `3` | 代理、订阅、连接页 |
| `j/k`、方向键、`g/G` | 选择、首尾；长列表自动滚动 |
| `Tab`、`h/l` | 代理组 / 节点面板 |
| `Enter` | 切换节点；订阅页提示到 Verge 切换 |
| `t` / `T`、`Esc` | 测当前节点 / 整组（最多四并发）、取消 |
| `/`、`Enter`、`Esc` | 中文/英文子串过滤、确认、清除；不做拼音转换 |
| `m` | `rule → global → direct` |
| `i`、`Tab` | 导入对话框、切换 URL / 可选名称字段 |
| `f`、`u`、`o` | 刷新用量、提示到 Verge 更新、打开 Verge |
| `x` | 立即关闭所选连接，按连接 ID 保持刷新后的选择 |
| `s` / `X` | 未运行时启动 / 运行时确认关闭 Verge；等待 socket 状态变化 |
| 鼠标滚轮 / 点击 | 选择行、切页和面板 |
| `r`、`?`、`q` / `Ctrl-C` | 刷新、帮助、退出 |

延迟 `<150ms` 为绿，`150–399ms` 为黄，`>=400ms` 或失败/零延迟为红，未测为 `--`。整组测试忽略节点过滤条件。URL 输入不回显，只显示字符数；日志和错误不包含 URL。

## Verge 2.4.7 订阅边界

依据 `flake.lock` 对应 nixpkgs 的 `clash-verge-rev` 2.4.7 src：

- `src-tauri/src/utils/resolve/scheme.rs:14–104` 提供 `clash://install-config?url=<encoded>`；TUI 调用 `clash-verge <link>`，让已运行的 Verge 自己获取并写入订阅。未运行时可按 `s` 启动；请求发出不代表导入成功，需要在 Verge 确认后按 `r` 重读。没有启动 GUI 的隔离验证必须加 `--no-verge`。
- URL 可包含多个 query 参数。但名称存在上游编码缺陷：`utils/server.rs:39–43` 转发链接时未编码整个参数；`resolve/scheme.rs:50–55` 又把 `url=` 后全部字符串作为 URL。名称放前会在运行实例转发中丢掉 URL，放后会丢失名称或混入订阅请求。因此直接导入只发送 URL；输入可选名称时明确引导到 Verge 完成，不静默丢弃名称。
- 更新是 `src/services/cmds.ts:57–59` 的内部 Tauri `update_profile`；选中订阅是 `src/pages/profiles.tsx:452–459` 的 `patch_profiles_config`。singleton server 仅有 scheme/visible/pac 路由，没有订阅更新/选择 API。TUI 使用说明对话框和“在 Verge 中打开”，不调用私有 Tauri IPC，不改 `profiles.yaml`。
- `resolve/scheme.rs:15` 将完整 deep link 写入 **Verge 自己的日志**。导入对话框明确显示此实际隐私限制；TUI 不记录链接、不写磁盘，不读取真实 API secret。

内核接口依据 [mihomo API 官方文档](https://wiki.metacubex.one/api/)。用量取自只读 `extra` 或 `subscription-userinfo`；未知配额/到期显示未知，不冒充无限流量。`expire=0` 显示“未知 / 不限”。

## 生命周期与隔离验证

`src/lifecycle.rs` 通过 `noctalia msg app-launch /run/current-system/sw/share/applications/clash-verge.desktop`
复用已锁定并由本仓库补丁公开的 AppProvider。它执行原生 desktop 启动策略：
`systemd-run --user --slice=app.slice`、`ExitType=cgroup`、`OOMPolicy=continue`，
以及 Noctalia 环境和 activation token；TUI 不复制或输出环境。可用
`MAYON_CLASH_DESKTOP` 指定桌面文件位置。URL deep link 仍由 GUI 官方 singleton 接口处理。

离线页面只显示“Clash 未运行 · s 启动”，后台每两秒检测；运行时顶部显示“运行”。
`X` 确认后只向本用户、`/nix/store/*-clash-verge-rev-*/.../clash-verge`
或 `.clash-verge-wrapped` 的 GUI 发 SIGTERM，不匹配 service 或 mihomo。
通过 pidfd 固定进程身份后再次读取 UID/exe，避免 PID 重用。停止后等待 socket 消失；
启动后等待 API 可连接，30 秒超时给出提示。关闭窗口可能仅隐藏到托盘；必须退出 GUI。

隔离测试可同时指定 `--test-verge-executable /absolute/compiled-fixture` 和
`--test-launcher /absolute/fixture-launcher`，仅精确匹配该 fixture 的规范可执行路径。
这两个选项必须成对、绝对路径；`--no-verge` 禁止启动与停止。测试不应调用真实 Noctalia。

Nix 显式设置 `programs.clash-verge.autoStart = false`，保留 serviceMode 的 root helper
以提供 TUN。Verge 自己的可变 auto-launch 设置不由 TUI/Nix 改写；既有用户若曾开启，
需在 GUI 内关闭一次。源码核验依据锁定 Noctalia `desktop_entry_launch.cpp`、
`process.cpp` 以及 Verge 2.4.7 `feat/window.rs::clean_async`、`utils/resolve/mod.rs` 信号处理。

## 维护与验证

`src/api.rs` / `profiles.rs` 保留上一轮纯模型和 API；`src/app.rs` 管交互与异步任务，
`src/ui.rs` 保留已确认的代理/订阅/连接布局。`src/theme.rs` 重导出共享 UI palette；
通用样式、边框、标记、弹窗、输入/帮助、终端生命周期与刷新骨架在 `mayon-ui`。
修改时先改纯数据模型，再改 `App::key`，最后改绘制。后台任务只通过 channel 返回数据。

在工作区运行 `cargo test -p clashtui-mayon`、
`cargo clippy --workspace --all-targets -- -D warnings` 和 `cargo fmt --all --check`。
Nix 的 `checks.mayon-tui` 一次构建全部 release 二进制、执行测试和 clippy。
构建不应用系统配置，截图必须使用私有 mihomo + GUI fixture、独立 HOME/XDG/D-Bus、
headless Sway 和真实 Kitty。旧 feature 删除仅迁移源码，不删除任何应用数据。
