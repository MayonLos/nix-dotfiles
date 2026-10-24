# Laptop network

Configures NetworkManager, IPv6, firewall trust for the Clash TUN interfaces, Clash Verge service/TUN mode, and proxy variables for the Nix daemon. A paired user aspect grants the NetworkManager group. It consumes no appearance or user profile data.

`default.nix`, `network.nix`, and `clash.nix` own the host network declarations; all Nix files are private. This feature assumes Clash's local SOCKS listener on port 7897 and keeps systemd-resolved enabled for DNS inside the tunnel.

Removing the feature withdraws these network and proxy declarations on activation. It does not erase NetworkManager connection profiles, Clash configuration/subscriptions, credentials, or network history.
