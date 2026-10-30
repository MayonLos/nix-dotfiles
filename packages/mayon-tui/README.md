# Mayon TUI workspace

All custom TUI source lives here. `default.nix` is the public Nix package
factory (`{ pkgs }`); `nix/pkgs.nix` publishes `pkgs.mayonTui`. One locked
`buildRustPackage` builds all binaries and runs workspace tests and clippy.
The `out` output contains all three commands; separate `clash`, `docker`, and
`ports` outputs allow features to install only their owned command.

| Crate | Command | Installation owner |
| --- | --- | --- |
| [ui](crates/ui/README.md) | shared library | all tools |
| [clash](crates/clash/README.md) | `clashtui-mayon` | `clash-tui` aspect in laptop-network |
| [docker](crates/docker/README.md) | `dockertui-mayon` | container-client |
| [ports](crates/ports/README.md) | `portstui-mayon` | port-tools (selected by the user binding) |

Features use `pkgs.mayonTui.<output>`; they never import a sibling feature's
private source. They own installation and configuration; desktops own their
bindings and window rules. Programs do not create services or write persistent state. Clash can read an
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
Clash offers paired fixture executable/launcher options and `--no-verge`;
Docker accepts `--host`; ports can run in an unprivileged user/network
namespace for synthetic listeners and process actions.
