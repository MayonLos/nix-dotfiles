# Laptop network

Configures NetworkManager, IPv6, firewall trust for the Clash TUN interfaces, Clash Verge service mode (the privileged service owns Mihomo/TUN), and proxy variables for the Nix daemon. A paired user aspect grants the NetworkManager group. It consumes no appearance or user profile data.

`default.nix`, `network.nix`, and `clash.nix` own the host network declarations; all Nix files are private. Clash is started and stopped by hand by opening or quitting Verge; nothing is forced through its local listener (port 7897), so the system works with Clash off. systemd-resolved stays enabled for DNS inside the tunnel.

Removing the feature withdraws these network and proxy declarations on activation. It does not erase NetworkManager connection profiles, Clash configuration/subscriptions, credentials, or network history.

Round 37 disables `programs.clash-verge.tunMode`, which in locked nixpkgs only creates a capability-bearing GUI wrapper. `serviceMode` stays enabled: the root helper starts Mihomo on the GUI’s `/clash/start` request. Historical boot0.log timing does not imply that the helper itself starts the core unconditionally. Avoiding capabilities on the GUI allows the portal to inspect its `/proc/<pid>/root`; it does not disable TUN in the user's Clash configuration. GTK widget assertions remain an upstream application issue. Recheck TUN, DNS and portal access after switching and relaunching the GUI; no runtime service was changed during implementation.


Round 47 keeps the `clash-tui` aspect ID here, installing only the public
`pkgs.mayonTui.clash` output. The old feature directory is removed; source and
maintenance move to [the Rust workspace](../../../packages/mayon-tui/README.md).
The user binding selects independent `port-tools` for listener diagnostics.
Neither tool owns persistent app data. Removing `clash-tui` only uninstalls its
binary; subscriptions, Verge state and proxy settings remain runtime owned.

`programs.clash-verge.autoStart = false` explicitly disables the Nix desktop
startup item. The root `clash-verge-service` helper remains available for TUN;
it accepts GUI requests, and is distinct from the GUI and Mihomo lifecycle.
The GUI's own mutable auto-launch setting is not rewritten or read by Nix or
the TUI. If previously enabled in Verge, disable it once in Verge settings;
this round does not edit existing user settings or autostart files. Opening
Verge starts its core; quitting (including confirmed TUI `X` / SIGTERM) runs
upstream cleanup and stops the core. Closing its window may only hide to tray.
