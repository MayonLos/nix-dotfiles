# Clash TUI

`clashtui-mayon` 是 Rust + ratatui 原型，通过本机 Unix socket 控制已有的 mihomo，读取 Clash Verge Rev 订阅元数据。名字明确区分上游 Clash TUI 项目，不占用含义模糊的 `cl`。不启动内核，不接管 TUN、系统代理或 GUI 生命周期。

## 输入与输出契约

选择 Den aspect `clash-tui` 会给 Home Manager 用户安装一个二进制。输入为实体的 `user.appearance`（已有 appearance schema，必须提供颜色）；没有新增 schema 选项，因此没有独立 `contract.nix`。`default.nix`、`checks.nix` 和 `package.nix` 是公开入口；包工厂参数为 `{ pkgs, palette }`。其余文件属于本功能实现。

运行时输入：

- 默认 socket：`$XDG_RUNTIME_DIR/clash-verge-rev/verge-mihomo.sock`。只走 Unix，不退回 TCP controller；不读取 Verge `config.yaml` 或 `secret`。若 socket 返回未授权，只显示操作失败，不尝试寻找密钥。
- 默认订阅文件：`$HOME/.local/share/io.github.clash-verge-rev.clash-verge-rev/profiles.yaml`。启动时、打开订阅页或按 `r` 时只读；只显示 `remote`、`local`，过滤 merge/script 辅助项。
- `/proxies`、`/configs`、`/version`、`/connections` 快照每两秒更新；`/traffic` 为持续 HTTP JSON 行流，连接中断会自动重连。状态栏明确显示 offline，流量失联显示 `--`，不伪造零流量。
- 刷新用量使用当前内核 `/configs` 的 mixed-port，经显式 HTTP 代理访问订阅 URL；可用 `--usage-proxy` 指定 HTTP/SOCKS 代理。没有端口就停止，不回退直连。HEAD 无响应头时尝试 GET，只读响应头，不读取或保存订阅正文；禁用重定向，防止凭据被静默送到别的主机。

输出为终端画面和用户明确触发的内核请求（选择节点、切换模式、测速、关闭连接）。本 feature 不拥有任何持久配置、缓存、订阅、日志或用户状态文件；用量刷新只保存在进程内存。取消测速会停止本地队列并忽略过期结果，已经送达内核的最多四个请求仍可能执行到其 5 秒超时（mihomo 的测速 handler 使用独立后台 context）。移除 feature 只卸载入口，保留 Verge 和所有应用数据。节点/模式修改由 mihomo/Verge 的已有策略决定是否持久化。

颜色由 Nix 从实体 palette 生成编译期常量。直接运行 Cargo 时，`build.rs` 读取仓库公开的 `appearance/appearance/onedark.nix`，没有第二套硬编码配色。字体由宿主 Kitty 提供，推荐系统现用的 Maple Mono NF CN。中文截断使用 `unicode-width`，选中行为淡底加蓝色左边线。

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
| `r`、`?`、`q` / `Ctrl-C` | 刷新、帮助、退出 |

延迟 `<150ms` 为绿，`150–399ms` 为黄，`>=400ms` 或失败/零延迟为红，未测为 `--`。整组测试忽略节点过滤条件。URL 输入不回显，只显示字符数；日志和错误不包含 URL。

## Verge 2.4.7 订阅边界

依据 `flake.lock` 对应 nixpkgs 的 `clash-verge-rev` 2.4.7 src：

- `src-tauri/src/utils/resolve/scheme.rs:14–104` 提供 `clash://install-config?url=<encoded>`；TUI 调用 `clash-verge <link>`，让已运行的 Verge 自己获取并写入订阅。现有实例常驻是此原型的运行前提；请求发出不代表导入成功，需要在 Verge 确认后按 `r` 重读。没有启动 GUI 的隔离验证必须加 `--no-verge`。
- URL 可包含多个 query 参数。但名称存在上游编码缺陷：`utils/server.rs:39–43` 转发链接时未编码整个参数；`resolve/scheme.rs:50–55` 又把 `url=` 后全部字符串作为 URL。名称放前会在运行实例转发中丢掉 URL，放后会丢失名称或混入订阅请求。因此直接导入只发送 URL；输入可选名称时明确引导到 Verge 完成，不静默丢弃名称。
- 更新是 `src/services/cmds.ts:57–59` 的内部 Tauri `update_profile`；选中订阅是 `src/pages/profiles.tsx:452–459` 的 `patch_profiles_config`。singleton server 仅有 scheme/visible/pac 路由，没有订阅更新/选择 API。TUI 使用说明对话框和“在 Verge 中打开”，不调用私有 Tauri IPC，不改 `profiles.yaml`。
- `resolve/scheme.rs:15` 将完整 deep link 写入 **Verge 自己的日志**。导入对话框明确显示此实际隐私限制；TUI 不记录链接、不写磁盘，不读取真实 API secret。

内核接口依据 [mihomo API 官方文档](https://wiki.metacubex.one/api/)。用量取自只读 `extra` 或 `subscription-userinfo`；未知配额/到期显示未知，不冒充无限流量。`expire=0` 显示“未知 / 不限”。

## 维护与验证

| 文件 | 职责 |
| --- | --- |
| `src/main.rs` | CLI 参数、终端恢复、输入循环 |
| `src/api.rs` | Unix HTTP 客户端、JSON 类型、路径编码、固定错误类别 |
| `src/profiles.rs` | Verge YAML、响应头、用量计算和 deep link 构造 |
| `src/app.rs` | 页面状态、刷新任务、并发测速/取消、Verge 回退、经代理用量请求 |
| `src/ui.rs` | ratatui 绘制、列表滚动、窄窗、帮助/导入弹窗 |
| `src/theme.rs`、`build.rs` | palette 生成、延迟颜色、字节单位、宽字符截断 |
| `Cargo.lock` | 固定 Rust 依赖；升级后重新测试解析和终端行为 |

先理解纯数据类型，再改 `App::key` 的行为，最后改 UI。异步任务只通过 `Update` channel 返回结果，不直接操作终端。`generation` 防止取消前的测速结果污染当前状态。连接快照排序并保留选中 ID，避免刷新后误关其他连接。

有 Rust 工具链时，在本目录运行 `cargo fmt --check`、`cargo clippy --all-targets -- -D warnings`、`cargo test`。测试覆盖 JSON/YAML/null 列表、响应头未知字段/溢出、延迟分界、中文截断、过滤/取消、连接选择稳定、HEAD→GET 经代理回退，以及宽/窄 terminal backend 渲染。

```sh
nix flake check --no-build --no-write-lock-file
nix build --no-link --no-write-lock-file .#checks.x86_64-linux.clash-tui
```

`default.nix` 显式登记同目录 `checks.nix`。该 derivation 构建 release 包，并执行 `cargo test` 和 `cargo clippy --offline --all-targets -- -D warnings`，没有额外 nixpkgs 实例。构建不应用系统配置；交互截图需要私有 mihomo、独立 HOME/XDG/D-Bus、无头 Sway 和真实 Kitty。此 feature 不安装 Mango 规则或快捷键，集成文本由主代理并入桌面功能。
