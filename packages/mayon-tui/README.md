# Mayon TUI workspace

All custom TUI source lives here. `default.nix` is the public Nix package
factory (`{ pkgs }`); `nix/pkgs.nix` publishes `pkgs.mayonTui`. One locked
`buildRustPackage` builds all binaries and runs workspace tests and clippy.
The `out` output contains both commands; the `clash` output also exposes
`mayon-clash-preflight` for the network service (source in `scripts/`). Separate `clash` and `tools` outputs allow features to install the independent
Clash client or the shared toolbox.

| Crate | Command | Installation owner |
| --- | --- | --- |
| [ui](crates/ui/README.md) | shared library | all tools |
| [clash](crates/clash/README.md) | `clashtui-mayon` | `clash-tui` aspect in laptop-network |
| [tools](crates/tools/README.md) | `mayon-tools` | mayon-tools aspect |
| docker / ports / serial / keys / voice | toolbox pages and CLI subcommands | existing features include mayon-tools |

Features use `pkgs.mayonTui.<output>`; they never import a sibling feature's
private source. They own installation and configuration; desktops own their
bindings and window rules. Docker/ports 不拥有持久配置。Clash native 试用版写入用户私有的订阅、设置与 runtime；
laptop-network 声明手动系统服务，程序本身不安装服务。Clash can read an
optional user-owned `~/.config/mayon-tui/clash.toml`.
Existing subscriptions, projects, containers and volumes stay user owned.

## Development

From the repository root:

```sh
nix develop
cd packages/mayon-tui
cargo run -p mayon-tools -- --help
cargo test --workspace --locked
cargo clippy --workspace --all-targets --locked -- -D warnings
cargo fmt --all --check
cargo build --release --workspace --locked
```

`Cargo.lock` is versioned. `nix/dev.nix` supplies the shared toolchain and
registers rustfmt with treefmt; `checks.mayon-tui` builds every release binary,
tests all crates and treats clippy warnings as errors. The One Dark constants
are generated at compile time by `ui/build.rs`: Nix supplies the repository
palette as JSON; plain Cargo reads the same public
`aspects/appearance/appearance/onedark.nix`. There is no duplicated palette.

Each tool keeps state on the UI thread and receives worker results through
channels. Network requests, following logs, stats and `/proc` scans do not
block drawing. The common terminal guard restores raw mode, alternate screen
and mouse capture on exit/panic. All tools support `?`, `/`, `q`, j/k, arrows,
wheel and click; narrow columns clip by Unicode terminal cell width.

To add a tool, add `crates/<name>` to the workspace, depend on `mayon-ui`, use
its chrome/table/dialog/terminal/refresh APIs, add parser and dangerous-action
behavior tests, add a binary output to `default.nix`, then select that output
from its responsible feature. Register the feature explicitly and document
its state ownership. Do not create another nixpkgs instance or Cargo lockfile.

## Isolation

Production invocations may contact real local services and confirmed actions
can change them. Run development against explicit private sockets and test
processes. Start every isolated runtime from `env -i` with a private HOME/XDG
and D-Bus/Wayland session. Never inspect or log an inherited environment. See
[agent workflow](../../docs/agent-workflow.md), sections 3 and 8, for screenshots.
Clash accepts `--data-dir`, `--socket`, `--mihomo`, `--systemctl`, and `--config`
paths for isolated data and service fixtures;
`mayon-tools docker` accepts `--host`; ports can run in an unprivileged user/network
namespace for synthetic listeners and process actions.

## 搜索与输入约定

保留的 TUI 使用 `mayon_ui::search` 和 `mayon_ui::input::TextInput`，共享库也供
keys、serial、bilitui 和 voice dashboard 使用。页面布局可独立演进，搜索匹配与
编辑状态不依赖布局。

- `/` 打开本地过滤并实时更新；Enter 保留过滤回到列表；输入中的 Esc 恢复打开前的
  过滤。列表中的 Esc 先清除已有过滤，再执行该页原有的返回或退出行为。
- 输入中 ↑/↓ 可以直接移动列表选择。列表支持 PgUp/PgDn、g/G 和滚轮；筛选和刷新按
  稳定 ID 保留选中项，被移除或不再匹配时选择第一项。无匹配时显示空状态和 Esc 提示。
- 过滤值在标题或状态行持续显示，列表显示匹配数/总数。命中字符使用 One Dark 黄色。
  查询按空白拆词并执行 AND，忽略 Unicode 大小写；每词依次尝试字面、拼音全拼、
  拼音首字母和短文本子序列（最多 80 个字符）。长日志与命令行不进行子序列匹配。
  `SearchText` 可缓存预处理，`SearchCache` 提供有界缓存；Latin 文本不计算拼音。
- TextInput 支持 ←/→、Home/End、Ctrl+A/E、Backspace/Delete、Ctrl+U（清光标前）、
  Ctrl+K（清光标后）、Ctrl+W/Alt+Backspace（删前词）。真实终端光标跟随字符与显示
  宽度，横向滚动不截断 UTF-8。未知 Ctrl/Alt 组合不插入字母。
- 终端启用 bracketed paste。粘贴只交给当前输入框；换行转空格，控制字符被过滤，
  单行长度上限 4096 个字符；没有输入框时忽略粘贴。表单与确认文本也使用相同编辑器。
- Serial 的 `/`（或 `f`）过滤记录，Ctrl+f 搜索命中位置，n/N 向后/向前循环定位，
  状态显示第 x/共 y 个。搜索与记录过滤分别保留状态。

## 工具箱与样式

Clash 和 bilitui 保留独立窗口。`mayon-tools` 用 `[` / `]` 切换 docker、ports、
serial、keys、voice；页面内部数字键保持各自含义。输入框编辑时方括号正常输入。
默认打开 ports，首次切换到 docker 才连接 Docker；只有显式 `ports --docker-map`
才查询 Docker 端口映射。每页首次打开才初始化，切走和 FocusLost 暂停被动刷新、
任务和流，返回时保留过滤、选中和子页。已明确启动的外部事务遵循各工具原有语义。
非交互子命令使用 `mayon-tools keys list --json`、`mayon-tools serial ...` 等形式。

公共 One Dark 样式用中性边框和三级文字色；键名蓝色、说明弱化，窄窗口只保留完整
键值对。弹窗有统一内边距，状态同时使用符号和文字；临时消息 5 秒后消失。
`Notice`、`Tone`、`modal`、`list_state` 和数值右对齐 helper 供页面复用。
终端启用焦点事件，事件循环仅在输入、数据变化或实际到期时唤醒和绘制。
日志、串口记录与搜索索引都有容量限制；空查询不建立拼音索引。

桌面 `Super+Shift+T` 已用于 switcher，工具箱采用 `Super+Shift+D`；
Clash 为 `Super+Shift+C`，bilitui 为 `Super+Shift+B`。录音改为专用
`Super+Shift+XF86Assistant` 松开触发，旧 `Super+Shift+V` 已移除。
截图功能仍由 Mango 的截图脚本提供，图库 TUI 已移除，原截图文件不作清理。
