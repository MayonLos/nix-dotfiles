# Remote access

Provides a closed-by-default SSH host endpoint. It enables socket-activated OpenSSH bound only to `127.0.0.1:22` and `[::1]:22`, while keeping the firewall closed, password and keyboard-interactive authentication disabled, and root login prohibited. It consumes no user or appearance input and currently defines no authorized key.

Inbound SSH requires deliberately changing the listen addresses, adding authorized keys and opening the firewall. No external interface or trusted Clash TUN can reach the loopback listener. The 2026-10-29 change is declarative only; verify the socket after system activation.

`default.nix` and `host.nix` own the NixOS SSH declarations; both are private. Removing the aspect removes the SSH socket/service configuration in a new system generation. It does not remove user SSH keys, known-hosts, client configuration, or other remote-access state.
