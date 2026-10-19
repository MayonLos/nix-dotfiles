{
  pkgs,
  home,
  host,
  palette,
}:
let
  python = pkgs.python3.withPackages (p: [ p.tomlkit ]);
  metadata = pkgs.writeText "desktop-contract.json" (
    builtins.toJSON {
      settings = home.programs.noctalia.settings;
      units = pkgs.lib.getAttrs [
        "noctalia"
        "fcitx5-daemon"
        "clipboard-bridge"
        "xrdb-merge"
      ] home.systemd.user.services;
      environment = home.systemd.user.sessionVariables;
      sharedTargets = home.nixDotfiles.graphicalSessionTargets;
      greeter = host.services.displayManager.noctalia-greeter.settings;
      inherit palette;
    }
  );
in
pkgs.runCommand "interactive-session-config" { nativeBuildInputs = [ python ]; } ''
  export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/config" XDG_CACHE_HOME="$TMPDIR/cache" XDG_STATE_HOME="$TMPDIR/state" XDG_DATA_HOME="$TMPDIR/data"
  mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$out"
  ${pkgs.lib.getExe home.programs.noctalia.package} config validate ${
    home.xdg.configFile."noctalia/config.toml".source
  } > "$out/noctalia.log" 2>&1 || { cat "$out/noctalia.log"; exit 1; }
  if grep -iE '\[WARN\]|warning:|\[ERROR\]' "$out/noctalia.log"; then exit 1; fi
  ${pkgs.lib.getExe home.wayland.windowManager.mango.package} -c ${
    home.xdg.configFile."mango/config.conf".source
  } -p > "$out/mango.log" 2>&1 || { cat "$out/mango.log"; exit 1; }
  if grep -iE 'conflict|unknown|invalid|error' "$out/mango.log"; then exit 1; fi
  python3 ${./resources}/test_reconcile_overrides.py -v > "$out/ownership.log" 2>&1 || { cat "$out/ownership.log"; exit 1; }
  python3 - ${metadata} ${home.xdg.configFile."noctalia/palettes/One-Dark-Darker.json".source} <<'PY'
  import json, re, sys
  m = json.load(open(sys.argv[1]))
  p = json.load(open(sys.argv[2]))
  roles = "Primary OnPrimary Secondary OnSecondary Tertiary OnTertiary Error OnError Surface OnSurface SurfaceVariant OnSurfaceVariant Outline Shadow Hover OnHover".split()
  assert set(p) == {"dark"}
  assert set(p["dark"]) == {"m" + role for role in roles} | {"terminal"}
  terminal = p["dark"]["terminal"]
  assert set(terminal) == {"background", "foreground", "cursor", "cursorText", "selectionBg", "selectionFg", "normal", "bright"}
  for key in ("normal", "bright"):
      assert set(terminal[key]) == set("black red green yellow blue magenta cyan white".split())
  def colors(node):
      for value in node.values():
          if isinstance(value, dict): colors(value)
          else: assert re.fullmatch(r"#[0-9a-fA-F]{6}", value), value
  colors(p)
  assert p["dark"]["mSurface"] == m["palette"]["bg"] == "#1f2329"
  settings = m["settings"]
  assert settings["theme"]["source"] == "custom" and settings["theme"]["mode"] == "dark"
  assert settings["theme"]["custom_palette"] == "One-Dark-Darker"
  assert "kitty" not in settings["theme"]["templates"]["builtin_ids"]
  assert "mango" not in settings["theme"]["templates"]["builtin_ids"]
  assert "noctalia-firefox" in settings["theme"]["templates"]["user"]
  assert "noctalia-mango" not in settings["theme"]["templates"]["user"]
  assert settings["shell"]["launch_apps_as_systemd_services"]
  for name, unit in m["units"].items():
      targets = m["sharedTargets"] if name in ("fcitx5-daemon", "xrdb-merge") else ["mango-session.target"]
      assert unit["Unit"]["PartOf"] == targets, name
      assert unit["Unit"]["After"] == targets, name
      assert unit["Install"]["WantedBy"] == targets, name
  noctalia = m["units"]["noctalia"]
  assert noctalia["Service"]["Restart"] == "on-failure"
  assert noctalia["Unit"]["StartLimitBurst"] == 3
  assert noctalia["Service"]["ExecStartPre"]
  env = dict(value.split("=", 1) for value in noctalia["Service"]["Environment"])
  assert env["QT_QPA_PLATFORMTHEME"] == "qt6ct" and env["XMODIFIERS"] == "@im=fcitx"
  assert not any("KEY" in key or "TOKEN" in key or "SECRET" in key for key in env)
  assert m["greeter"]["appearance"]["palette"]["surface"] == "#1f2329"
  assert m["greeter"]["output"]["scales"] == "eDP-1:1.5"
  PY
''
