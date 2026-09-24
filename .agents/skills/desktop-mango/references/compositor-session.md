# Compositor configuration and session

Mango's Home Manager settings are in `modules/home/wm/mango/config.nix`; its system module is `modules/system/desktop/mango.nix`. The flake pins Mango and its compatible wlroots/scenefx stack together.

## Config semantics

- The Home Manager module flattens nested settings to underscore-separated keys and repeats keys such as `bind`, `windowrule`, `tagrule`, and `monitorrule` from lists. `extraConfig` is appended at the end.
- Check keys and dispatcher names in the pinned Mango source (`parse_option()` and `parse_func_name()` in `src/config/parse_config.c`). The generated config is parser-checked at build time; this will not catch values that parse but no-op or behave differently than expected.
- A bind needs modifier, key, and dispatcher fields. Layout, master factor, and master count belong on tag rules, not monitor rules. Inspect the relevant dispatcher implementation for numeric conventions before changing a binding.
- `setmfact` follows dwm-style arguments here: values below `1` are deltas; values at least `1` encode an absolute factor as `value - 1`. For example, `1.55` selects `0.55`, while `0.55` is a delta. Check this in the currently pinned source if the dispatcher changes.
- Keep `source-optional` for Noctalia's generated Mango theme file: Noctalia may not have written it when Mango first parses its config.

## Session startup and environment

`systemd.enable` defines the Mango session target; the module's generated `autostart_sh` starts it and updates the D-Bus activation environment. Keep `autostart_sh` non-empty for session-managed units to start. Put session launches there rather than relying on an unrelated `exec-once`.

Mango is launched directly, so do not assume it sourced Home Manager's shell session variables. `config.nix` mirrors suitable `home.sessionVariables` into Mango `env=` settings. Values needing shell expansion are filtered because Mango does not evaluate shell syntax. Check a spawned child for effective variables; Mango's `/proc/.../environ` reflects its original exec environment, before config parsing.

At this host's fractional scale, `xwayland_ignore_scale` in Mango and `Xft.dpi` delivered by `modules/home/base/xresources.nix` work as a pair. Re-measure client geometry and DPI before changing either; see the input/clipboard reference for the client protocol distinction.

The `xrdb-merge` user service exists because Home Manager's activation may not have `DISPLAY` and `xsession.profileExtra` is not sourced by Mango. Check `xrdb -query` and the service state rather than only reading `~/.Xresources`.
