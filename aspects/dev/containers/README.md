# Rootless containers

Offers two selections: `container-client` installs only Docker CLI; `local-containers` includes that client and enables a per-user rootless daemon on the host. The local feature routes its host module once through `local-containers-host` and sets the user's socket endpoint.

Outputs include a rootless Docker user service, an on-demand Docker API socket, and a weekly build-cache prune timer. At login, `docker.socket` creates the per-user `%t/docker.sock` listener without starting the daemon. The first `docker` or `docker compose` request starts `docker-proxy.service`; that service starts the rootless daemon and forwards the request to its private `%t/docker-private.sock` endpoint. The public socket is mode `0600` and belongs to the selected user.

The daemon remains running after the client exits. Automatic idle shutdown is intentionally disabled so builds and other long-running tasks are not interrupted. The daemon keeps nixpkgs' `Restart=always` behavior and existing container restart policies. Since the daemon no longer starts at login, restart-policy containers are restored on the first Docker request after login, rather than immediately at login; a weekly prune request can also be the first request. This is the demand-start tradeoff and does not change container metadata or data. The weekly persistent prune timer still runs `docker builder prune` for cache older than seven days; it does not prune stopped containers, images, or volumes. `docker.socket` and the daemon exist only for accounts that select `local-containers`; the host module disables the upstream global user-unit installation.

Socket forwarding is checked with concurrent requests against an isolated Unix-socket backend by the `rootless-docker-socket-proxy` check. This exercises systemd's socket activation helper and `systemd-socket-proxyd`; it does not substitute for testing a real rootless daemon, Compose, image builds, or daemon/container restart behavior after applying the configuration.

The first activation needs an ordered handover: the old running daemon may still own `%t/docker.sock`, while the new unit uses `%t/docker-private.sock`. In a planned container maintenance window, stop the old daemon before starting the new public socket/proxy; do not unlink a socket owned by a running daemon. Confirm the merged user units and socket paths, then test demand startup and existing restart-policy workloads. This round does not perform that handover or restart any user service. `checks.nix` is the explicit public test hook; `resources/test_socket_activation.py` owns only isolated test sockets/processes.

`default.nix`, `home.nix`, and `host.nix` are private implementation files. Removing `container-client` removes the client package; removing `local-containers` also removes service and socket declarations on activation. Container writable layers, images, named volumes, and bind-mounted project data are user data and are not cleared by this feature.


`container-client` also installs `pkgs.mayonTui.tools` (`mayon-tools docker`),
the Docker output of the shared [Rust workspace](../../../packages/mayon-tui/README.md).
This places the client beside its Engine/Compose CLI rather than in a desktop
feature, so it works in a terminal or over SSH. The TUI uses the public socket,
never the private daemon socket; it does not declare a new service or own
Docker data. Explicit confirmed actions may modify containers/images/volumes;
volume deletion has two confirmations and no automatic volume pruning.
Stopping the daemon from the TUI pauses polling until the user reconnects, so
the public demand socket can remain available. See the
[crate README](../../../packages/mayon-tui/crates/docker/README.md) for keys and
API details. Removing the client removes the executable and leaves Docker data.
