# Listening port tools

`port-tools` installs the public `pkgs.mayonTui.tools` output (`mayon-tools ports`).
It belongs to network diagnostics: listeners exist independently of Docker and
of a desktop session. The user binding selects it beside the host’s `laptop-network`; other
accounts may select it independently. There are no schema inputs, persistent configuration or services.
The program reads `/proc`; only explicit confirmed user actions signal the
current user's processes. Removing the feature only removes its executable.

Source, development, tests and key bindings live in the public
[workspace](../../../packages/mayon-tui/README.md) and
[ports crate](../../../packages/mayon-tui/crates/ports/README.md).
`default.nix` is the sole feature entry; package implementation is private to
`packages/mayon-tui/default.nix`. Desktop bindings remain owned by the desktop.
