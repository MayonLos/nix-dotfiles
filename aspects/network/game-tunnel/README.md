# Game tunnel

Publishes a local game server (Minecraft) through a public frp relay, for friends outside the LAN. The relay is the Tencent Lighthouse server; it is a hand-managed Debian host, not part of this repository.

## Inputs

User schema `gameTunnel` (`contract.nix`): relay address and control port, the runtime token file, and named proxies (`localPort` on 127.0.0.1 → `remotePort` on the relay, tcp or udp). The token comes from a sops secret declared in the host's inventory; the token value never enters the Nix store.

## Outputs

- `game-tunnel` command: `start`, `stop`, `status`, `log`.
- User unit `game-tunnel.service` running `frpc` with a generated TOML in the store. It has no login wants or timer; it runs only between `game-tunnel start` and `stop` (or logout), and retries every 10 s while the relay or network is unreachable.
- frpc reads the token through `auth.tokenSource` and wraps the control connection in TLS.

## Relay side (not managed here)

On the relay, as of 2026-11-06: static frps 0.66.0 (built from this repo's nixpkgs as `pkgsStatic.frp`) at `/usr/local/bin/frps`; `/etc/frp/frps.toml` binds 7000, forces TLS, allows only port 25565 and reads the token from `/etc/frp/token` via systemd `LoadCredential`; `frps.service` runs with `DynamicUser`; nftables opens tcp 7000 and 25565. Client and relay versions must stay compatible when nixpkgs updates frp.

## Owned files and removal

Owns nothing in the home directory besides the generated unit and command. Removing the feature stops publishing; the relay keeps listening until `frps` is disabled there, and the sops secret stays until deleted from `secrets/secrets.yaml`.
