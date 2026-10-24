# Remote access

Provides a closed-by-default SSH host endpoint. It enables socket-activated OpenSSH while keeping the firewall closed, password and keyboard-interactive authentication disabled, and root login prohibited. It consumes no user or appearance input and currently defines no authorized key.

`default.nix` and `host.nix` own the NixOS SSH declarations; both are private. Removing the aspect removes the SSH socket/service configuration in a new system generation. It does not remove user SSH keys, known-hosts, client configuration, or other remote-access state.
