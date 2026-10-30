# GameMode package extension

This package factory applies the repository's small GameMode patch to the
locked nixpkgs GameMode derivation. It adds support for
`[general] desiredgov=ignore`: GameMode then leaves CPU governor management to
the host's power profile service and does not invoke `pkexec` for governor
changes. It also preserves upstream's `ioprio=off` sentinel instead of
clamping it to priority zero, and gives a non-empty error when a client request
is rejected without a D-Bus error. Other GameMode actions and client
registration remain enabled. A separate client patch checks `dbus_connection_send_with_reply` and the pending-call pointer before blocking: programs such as Steam runtime lsof close the client library’s cached D-Bus socket before their preload destructor runs. Upstream then passes NULL to libdbus and aborts; this package reports the disconnect and lets the program finish. It does not make session-wide preload desirable.

The patch targets GameMode 1.8.2's
`daemon/gamemode-context.c::game_mode_set_governor`,
`daemon/gamemode-config.c::config_get_ioprio_value`, and
`lib/client_impl.c::gamemode_request`. Check it against the currently locked
source before updating nixpkgs. The factory accepts the existing
`gamemode` derivation and the existing `runCommandCC` builder; it does not import nixpkgs or create a second
package set.

Public export `pkgs.gamemode.runtimeProbe` is a tiny Linux close-fds executable for the VM regression test. It establishes no services and writes no files. Owned files are `default.nix`, `ppd-governor.patch`, `client-disconnect.patch` and `tests/close-fds.c`. Removing this package
extension restores upstream GameMode behavior; no runtime configuration or
user data is owned here.
