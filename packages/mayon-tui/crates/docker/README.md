# dockertui-mayon

A Rust terminal client for the Docker Engine API. It reads and modifies the selected Docker daemon only after an explicit keyboard action; the TUI does not start a daemon on its own. It uses `DOCKER_HOST` when supplied, otherwise `$XDG_RUNTIME_DIR/docker.sock` (the rootless on-demand socket exposed by `aspects/dev/containers`). Only `unix://` endpoints are accepted.

## Pages and keys

- `1` containers grouped by `com.docker.compose.project`, with daemon status, compact published ports, live CPU and memory. `Enter` opens details with the full image, status, and host bind IP mappings.
- `2` images, sizes, tags and dangling status.
- `3` volumes, size/refcount when the daemon provides usage metadata. `d` asks twice and names the volume before deletion; no automatic volume prune exists.
- `4` Engine version and `system/df`; `c` confirms dangling-image cleanup and `b` confirms build-cache cleanup with an estimated reclaimable amount. The overview reports Docker's actual `SpaceReclaimed` after cleanup.
- `s` toggles selected container, `r` restarts it, `p` starts stopped members or stops running members of its Compose project, and `R` confirms restarting every project member. `l` follows logs, `j/k` scroll and `/` filters. `e` opens a new Kitty class `mayon-docker-exec` and runs `docker exec -it NAME bash` (the shell is selected using the exec API probe, falling back to `sh`). `d` confirms container/image removal. `S` asks before stopping `docker.service` and `docker-proxy.service`; it is available only for the standard local `%t/docker.sock`, to avoid stopping units unrelated to a custom `DOCKER_HOST`. After stopping, polling is suspended so it cannot immediately reactivate the demand socket. `s` resumes the view.
- `j/k`, arrows, wheel, and click select. `/` filters container name/image/project. `Enter` shows container details (`Esc` closes), `?` help, `q` exit.

Polling and streaming use Tokio tasks and return through channels. Docker logs decode both Engine multiplexed stdout/stderr frames and raw TTY streams after checking the container inspect endpoint. Container lists are grouped by Compose project and sorted by project/name; `o` cycles container ordering. The initial unavailable socket is presented as “Docker 启动中…”, reflecting socket activation. Errors avoid printing request URLs or environment values.

## Develop and maintain

Run from the workspace root:

```sh
cargo run -p dockertui-mayon
cargo test -p dockertui-mayon
cargo clippy -p dockertui-mayon --all-targets -- -D warnings
cargo run -p dockertui-mayon -- --help
```

`--help` and `--version` exit without contacting Docker. `--host
unix:///path/docker.sock` explicitly selects a socket and takes precedence over
`DOCKER_HOST`. Otherwise the command uses `DOCKER_HOST`, then
`$XDG_RUNTIME_DIR/docker.sock`.

`api.rs` owns Engine paths and JSON models; `app.rs` owns selection, actions and rendering; `main.rs` owns CLI options and the terminal event loop. API version is pinned to v1.47 per the [official Engine API reference](https://docs.docker.com/reference/api/engine/version/v1.47/); update the endpoint and response tests together when changing it. `/system/df` supplies volume usage and build-cache `InUse`/`Shared`. The reclaim estimate includes entries Docker marks unused and unshared; it is approximate, and Docker's `SpaceReclaimed` is shown after pruning. Destructive operations stay behind confirmation states. In particular, deleting volumes always requires two `y` presses and shows the exact volume name. Removing containers uses `v=false` to preserve volumes.

This crate does not own Docker daemon units, user data or persistent configuration. Removing the aspect only removes the program. Integration against a real daemon and Kitty exec window still needs separate session verification.
