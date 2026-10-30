# Noctalia Clash status

`default.nix { pkgs; }` exports the read-only `noctalia-clash-status` command.
It probes the existing native and Verge Unix controllers with bounded timeouts,
returns only a backend label and instantaneous up/down rates, and reports stale
sockets or simultaneous controllers explicitly. It never reads configuration,
credentials or subscriptions, calls a TCP controller, or starts/stops anything.
No files or persistent state are owned. Removing the package preserves all data.
