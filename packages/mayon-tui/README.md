# Mayon TUI workspace

All custom TUI source lives here. `default.nix` is the public Nix package
factory (`{ pkgs }`); `nix/pkgs.nix` publishes `pkgs.mayonTui`. One locked
`buildRustPackage` builds all binaries and runs workspace tests and clippy.
The `out` output contains all three commands; the `clash` output also exposes
`mayon-clash-preflight` for the network service (source in `scripts/`). Separate `clash`, `docker`, and
`ports` outputs allow features to install only their owned command.

| Crate | Command | Installation owner |
| --- | --- | --- |
| [ui](crates/ui/README.md) | shared library | all tools |
| [clash](crates/clash/README.md) | `clashtui-mayon` | `clash-tui` aspect in laptop-network |
| [docker](crates/docker/README.md) | `dockertui-mayon` | container-client |
| [ports](crates/ports/README.md) | `portstui-mayon` | port-tools (selected by the user binding) |

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
cargo run -p portstui-mayon -- --help
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
Docker accepts `--host`; ports can run in an unprivileged user/network
namespace for synthetic listeners and process actions.

## 搜索与输入约定

保留的 TUI 使用 `mayon_ui::search` 和 `mayon_ui::input::TextInput`，共享库也供
keys、shots、serial 和 voice dashboard 使用。页面布局可独立演进，搜索匹配与
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
