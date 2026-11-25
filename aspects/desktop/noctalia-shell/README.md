# noctalia-shell

Shared Noctalia v5 shell for every selectable session (Mango, Umbriel and
Hyprland). It owns the shell configuration, the palette, and the systemd user
services that start the shell and its companions from each compositor's session
target.

## Inputs

`user.appearance` (One Dark palette, fonts, cursor, `reducedMotion`); the
upstream Noctalia package from `pkgs.local.noctaliaDesktop.noctalia`.

## Outputs

| Path / unit | Writer |
|---|---|
| `~/.config/noctalia/config.toml` | `noctalia.nix` (Home Manager, TOML generated) |
| `~/.config/noctalia/palettes/one-dark.json` | `noctalia.nix` |
| `noctalia.service` | `services.nix`; `Type=notify`, `WantedBy` the three session targets |
| `polkit-gnome-authentication-agent-1.service` | `services.nix` |
| `clipboard-bridge.service` | `services.nix` + `clipboard-bridge.nix` |

Compositors import `WAYLAND_DISPLAY`/`XDG_SESSION_TYPE` before starting their
target (Mango via the HM module's systemd hook, Umbriel via `start-umbriel`,
Hyprland via the HM module), so one set of services works in all three.

## Optimizations

- `shell.offline_mode = true` removes the shell's recurring HTTP (palette,
  weather, geolocation); `weather`, `calendar`, `location.auto_locate` and
  community templates are disabled.
- `screen_time_enabled = false`, telemetry off, clipboard history capped at 50.
- `system.monitor` only samples CPU and memory; GPU/network/disk polls are 0.
- Animations follow `palette.reducedMotion`.
- Bar remains 30px, fully transparent, One Dark palette v2; widgets are the
  same in all sessions.

## Removal

Delete this feature, its include from the three session aspects, and the
`noctalia-benchmark` include; the shell packages and config disappear. Noctalia
state (`~/.local/state/noctalia`) and cache are user data and stay.
