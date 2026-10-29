# portstui-mayon

Linux listener viewer for TCP and UDP over IPv4/IPv6. It reads `/proc/net/{tcp,tcp6,udp,udp6}` and associates socket inodes with `/proc/<pid>/fd`, then reads process metadata when permissions allow. The view refreshes every two seconds and preserves selection by protocol, endpoint, PID and inode. Processes hidden by procfs permissions appear as `系统` and are never signal targets.

## Run and develop

From `packages/mayon-tui`:

```sh
cargo run -p portstui-mayon
cargo test -p portstui-mayon
cargo clippy -p portstui-mayon --all-targets -- -D warnings
```

The tool can read Docker port mappings with a read-only Engine `GET /containers/json?all=1` request. Mapping uses protocol, published port and published IP; wildcard binds match an address only within the same IP family, so unrelated TCP/UDP or host-IP listeners are not mislabeled. Duplicate matching names are listed together. A custom `DOCKER_HOST=unix:///...` is honored. The standard `$XDG_RUNTIME_DIR/docker.sock` is queried only when `$XDG_RUNTIME_DIR/docker-private.sock` already exists, even when `DOCKER_HOST` explicitly names that standard socket. Without `DOCKER_HOST`, it uses the same running-daemon gate. A non-Unix `DOCKER_HOST` is respected by declining to query a different socket. `--docker-map` explicitly forces the standard local socket query and can activate the on-demand Docker service. Requests have a one second timeout.

## Keys

`j/k` or arrows select; wheel scrolls. `/` filters; `s` cycles sorting by port, protocol, PID, process and address. `d`/Enter opens a large scrollable detail view with cwd, parent PID and the full command; j/k, arrows and PgUp/PgDn scroll it. `o` opens `http://localhost:<port>`; `c` copies the numeric port with `wl-copy`. `x` opens the confirmation. Press `y` to send SIGTERM to a process owned by the current uid, or press `k` to enter a second confirmation before SIGKILL; press `y` there to send it. There is no direct SIGKILL key. Escape cancels either confirmation. PID identity is rechecked by uid and `/proc/<pid>/stat` start ticks, then signalled through Linux pidfd; if pidfd is unavailable, the action is refused.

`?` shows the in-app help, `--help`/`--version` exit before scanning or connecting, and `q` exits. Common development ports are visually emphasized in the address column by their numeric value; wildcard IPv4/IPv6 binds are marked `对外`, loopback (`127/8`, `::1`) is `本机`, and other specific interface addresses are `指定接口`.
