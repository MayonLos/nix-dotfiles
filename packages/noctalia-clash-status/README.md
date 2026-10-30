# Noctalia Clash status

`default.nix { pkgs; }` exports the read-only `noctalia-clash-status` command.
It probes the native Mihomo Unix controller with bounded timeouts,
returns its status and instantaneous up/down rates, and reports stale
sockets explicitly. It never reads configuration,
credentials or subscriptions, calls a TCP controller, or starts/stops anything.
No files or persistent state are owned. Removing the package preserves all data.
