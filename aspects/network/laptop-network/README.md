# Laptop network

Configures NetworkManager, IPv6, firewall trust for the Clash TUN interfaces, Clash Verge service mode (the privileged service owns Mihomo/TUN), and proxy variables for the Nix daemon. A paired user aspect grants the NetworkManager group. It consumes no appearance or user profile data.

`default.nix`, `network.nix`, and `clash.nix` own the host network declarations; all Nix files are private. This feature assumes Clash's local SOCKS listener on port 7897 and keeps systemd-resolved enabled for DNS inside the tunnel.

Removing the feature withdraws these network and proxy declarations on activation. It does not erase NetworkManager connection profiles, Clash configuration/subscriptions, credentials, or network history.

Round 37 disables `programs.clash-verge.tunMode`, which in locked nixpkgs only creates a capability-bearing GUI wrapper. `serviceMode` stays enabled: boot0.log shows the root service successfully starting Mihomo through `/clash/start`. Avoiding capabilities on the GUI allows the portal to inspect its `/proc/<pid>/root`; it does not disable TUN in the user's Clash configuration. GTK widget assertions remain an upstream application issue. Recheck TUN, DNS and portal access after switching and relaunching the GUI; no runtime service was changed during implementation.
