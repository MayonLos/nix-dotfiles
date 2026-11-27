# noctalia-shell

The single Noctalia v5 shell for the Mango session. It owns the shell
configuration, the palette, and the systemd user services that start the
shell and its companions from the compositor's session target.

## Inputs

`user.appearance` (One Dark palette, fonts, cursor, `reducedMotion`); the
upstream Noctalia package from `pkgs.local.noctaliaDesktop.noctalia`.

## Outputs

| Path / unit | Writer |
|---|---|
| `~/.config/noctalia/config.toml` | `noctalia.nix` (Home Manager, TOML generated) |
| `~/.config/noctalia/palettes/one-dark.json` | `noctalia.nix` |
| `~/Pictures/Wallpapers/managed` | `noctalia.nix`; HM link to the appearance factory's 18-image link farm. The sibling `local/` directory is user data and is never written here. |
| `~/.local/share/noctalia/plugins/hideclients/{plugin.toml,indicator.luau}` | `noctalia.nix`; read-only local Noctalia plugin. |
| `noctalia.service` | `services.nix`; `Type=notify`, `WantedBy` the Mango session target |
| `polkit-gnome-authentication-agent-1.service` | `services.nix` |
| `clipboard-bridge.service` | `services.nix` + `clipboard-bridge.nix` |

The Mango Home Manager module imports `WAYLAND_DISPLAY`/`XDG_SESSION_TYPE`
into the user manager before starting the target, so one set of services
works for the session.

## Optimizations

- `shell.offline_mode = true` removes the shell's recurring HTTP (palette,
  weather, geolocation); `weather`, `calendar`, `location.auto_locate` and
  community templates are disabled.
- `screen_time_enabled = false`, telemetry off, clipboard history capped at 50.
- `system.monitor` samples CPU/memory at 2 s, GPU at 0, and network/disk at 3 s/10 s only for status displays.
- Animations follow `palette.reducedMotion`.
- Bar remains 30px, fully transparent, One Dark palette v2; widgets are the
  same in all sessions. The palette maps `on_surface`/`on_surface_variant` to
  the `brightFg`/`fg` text roles, workspace tags use those two roles plus
  `primary` for focus, and the clock shows `%m月%d日 %H:%M`.
- OSD is anchored `bottom_center` (offset 48) so it cannot cover the top-right
  notification stack. The wallpaper panel browses `~/Pictures/Wallpapers`.
- The local `hideclients` plugin restores the mangobar-era minimized-window
  counter: an eye-off glyph plus the count from `mmsg get all-monitors`
  (`hide_clients` summed over monitors), hidden at zero in One Dark `muted`.
  Clicking restores the latest minimized client through
  `mmsg dispatch toggle_scratchpad`. The `mmsg` path is substituted at build
  time instead of relying on the service PATH, and the widget stays hidden in
  sessions without that IPC.

## Removal

Delete this feature, its include from the three session aspects, and the
`noctalia-benchmark` include; the shell packages, config and the local plugin
disappear. Noctalia state (`~/.local/state/noctalia`) and cache are user data
and stay.
