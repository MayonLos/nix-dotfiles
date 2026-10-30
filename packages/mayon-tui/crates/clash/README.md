# mayon-clash TUI

The Clash TUI manages the system `mayon-clash.service` and its native Mihomo controller. It stores subscriptions and mutable settings under `~/.local/share/mayon-clash`; it does not manage another Clash application or remove user data.

## Usage

Run `clashtui-mayon` for the interactive terminal UI. It can also be used as a script entrypoint:

```sh
clashtui-mayon profile add [name] < subscription-url.txt
clashtui-mayon profile list
clashtui-mayon profile update <id|all>
clashtui-mayon profile use <id>
clashtui-mayon profile rename <id> <name>
clashtui-mayon profile url <id> < subscription-url.txt
clashtui-mayon profile delete <id> --yes
clashtui-mayon settings <key> <value>
clashtui-mayon service start|stop
```

The TUI supports pages for overview, proxies, subscriptions, connections, rules, logs, and tools. The subscription page can add, update, select, rename, edit, and remove subscriptions. Starting the service requires a selected subscription. Service activation is manual; quitting the TUI leaves the service running.

## Data and configuration

The native data directory contains:

| File | Purpose |
|---|---|
| `subscriptions.toml` | Subscription index, current selection, names, URLs, update timestamps and usage metadata |
| `subscriptions/<id>.yaml` | Cached subscription body, merged with local settings before validation |
| `settings.toml` | TUN, routing mode, IPv6, LAN access, log level, mixed port and baseline configuration |
| `config.yaml` | Generated runtime configuration consumed by Mihomo |
| `writer.lock` | Serializes TUI, CLI and automatic subscription updates |

Private files are written with restrictive permissions. Subscription URLs may include credentials and are only displayed in redacted form. Downloads identify as `clash.meta/mayon-clash` so providers that select Clash-compatible YAML by User-Agent can continue to serve a compatible format. Subscription bodies are validated with Mihomo before replacing a cache or runtime config. Changes are transactional and roll back on validation or hot-reload failure.

The baseline is captured in `settings.toml` and reused on subsequent changes. Existing settings keep their saved baseline. If settings are absent or the baseline field is missing, built-in defaults supply TUN, DNS, sniffer, and profile configuration; no other application's configuration is read.

The TUI preferences file is `~/.config/mayon-tui/clash.toml`. It may set `test_url`, `timeout_ms`, `concurrency`, `default_sort`, and `default_page`. Old preference files that also contain a `backend` key remain readable; the key is ignored.

## Service behavior

The service is `mayon-clash.service`, with its controller at `/run/mayon-clash/mihomo.sock`. The TUI and CLI use this Unix socket and do not fall back to a TCP controller. Stopping the service disables TUN and waits for the socket to disappear. The preflight script validates the generated configuration and seeds missing geodata files from immutable package resources.

No application data is deleted when the TUI or service is removed. Legacy Clash Verge files, if present, remain in the user's home directory and can be removed manually after the user decides whether to keep their subscriptions.
