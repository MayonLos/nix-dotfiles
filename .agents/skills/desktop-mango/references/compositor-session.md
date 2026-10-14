# Compositor configuration and session

Mango's Home Manager settings are in `modules/home/wm/mango/config.nix`; its system module is `modules/system/desktop/mango.nix`. The flake pins Mango and its compatible wlroots/scenefx stack together.

## Config semantics

- The Home Manager module flattens nested settings to underscore-separated keys and repeats keys such as `bind`, `window_rule`, `tag_rule`, and `monitor_rule` from lists. `extraConfig` is appended at the end.
- The 2026-10-14 pin uses underscore names, including `key_mode`, `source_optional`, `border_px`, and rule fields such as `app_id` / `is_floating`. Old spellings are rejected; migrate configuration and generated theme templates together.
- Check keys and dispatcher names in the pinned Mango source (`parse_option()` in `src/config/option_defs.c` and `parse_func_name()` in `src/config/binding_parse.c`). The generated config is parser-checked at build time; this will not catch values that parse but no-op or behave differently than expected.
- A bind needs modifier, key, and dispatcher fields. Layout, master factor, and master count belong on tag rules, not monitor rules. Inspect the relevant dispatcher implementation for numeric conventions before changing a binding.
- `setmfact` follows dwm-style arguments here: values below `1` are deltas; values at least `1` encode an absolute factor as `value - 1`. For example, `1.55` selects `0.55`, while `0.55` is a delta. Check this in the currently pinned source if the dispatcher changes.
- Keep `source_optional` for Noctalia's generated Mango theme file: Noctalia may not have written it when Mango first parses its config.
- `noctalia.nix` uses the upstream Mango palette as a user template with a reload-only hook. Its `noctalia-colors.conf` output avoids old palette keys; the builtin hook does not recognize `source_optional` and would append to the read-only Home Manager config.

## Session startup and environment

`systemd.enable` defines the Mango session target; the module's generated `autostart_sh` starts it and updates the D-Bus activation environment. Keep `autostart_sh` non-empty for session-managed units to start. Put session launches there rather than relying on an unrelated `exec_once`.

Mango is launched directly, so do not assume it sourced Home Manager's shell session variables. `config.nix` mirrors suitable `home.sessionVariables` into Mango `env=` settings. Values needing shell expansion are filtered because Mango does not evaluate shell syntax. Check a spawned child for effective variables; Mango's `/proc/.../environ` reflects its original exec environment, before config parsing.
The pinned parser caps configuration values at 255 bytes, so the environment mirror also filters longer entries such as `FZF_DEFAULT_OPTS`; shells still load them from Home Manager session variables.

At this host's fractional scale, `xwayland_ignore_scale` in Mango and `Xft.dpi` delivered by `modules/home/base/xresources.nix` work as a pair. Re-measure client geometry and DPI before changing either; see the input/clipboard reference for the client protocol distinction.

The `xrdb-merge` user service exists because Home Manager's activation may not have `DISPLAY` and `xsession.profileExtra` is not sourced by Mango. Check `xrdb -query` and the service state rather than only reading `~/.Xresources`.

Cursor sizing: `lib/desktop.nix` shares `primaryOutputScale` between Mango and
Noctalia Greeter. Greeter auto-DPI used 2.0 on the 2560x1600, 340x210 mm panel
(2026-10-08 journal), while Mango used 1.5. Pinning the same scale keeps the
login UI and cursor consistent. For X11/Pyglet windows, `xrdb-merge` also runs
`xsetroot -cursor_name left_ptr` after loading Xresources: XFixes measured the
inherited default bitmap as 32x32 before and 24x24 after, despite an unchanged
`Xcursor.size=24`. Do not compensate by shrinking the shared cursor size.
