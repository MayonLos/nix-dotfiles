# Rootless containers

Offers two selections: `container-client` installs only Docker CLI; `local-containers` includes that client and enables a per-user rootless daemon on the host. The local feature routes its host module once through `local-containers-host` and sets the user's socket endpoint.

Outputs include the generated rootless Docker user service, a weekly build-cache prune timer, and the Docker socket session variable. Pruning is limited to builder cache older than seven days; it does not prune stopped containers or volumes. The host module disables the global user-unit installation so only selected accounts get the merged unit.

`default.nix`, `home.nix`, and `host.nix` are private implementation files. Removing `container-client` removes the client package; removing `local-containers` also removes service and socket declarations on activation. Container writable layers, images, named volumes, and bind-mounted project data are user data and are not cleared by this feature.
