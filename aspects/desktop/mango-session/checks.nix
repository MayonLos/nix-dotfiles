{
  pkgs,
  home,
  nixos,
  appearance,
  ...
}:
let
  mango = home.wayland.windowManager.mango.settings;
  metadata = pkgs.writeText "unified-noctalia-session.json" (
    builtins.toJSON {
      targets = [
        "mango-session.target"
      ];
      graphicalSessionTargets = home.nixDotfiles.graphicalSessionTargets;
      noctalia = {
        wantedBy = map (unit: if pkgs.lib.hasSuffix ".target" unit then unit else "${unit}.target") (
          home.systemd.user.services.noctalia.Install.WantedBy or [ ]
        );
        execStart = home.systemd.user.services.noctalia.Service.ExecStart or "";
      };
      polkit = {
        wantedBy = map (unit: if pkgs.lib.hasSuffix ".target" unit then unit else "${unit}.target") (
          home.systemd.user.services.polkit-gnome-authentication-agent-1.Install.WantedBy or [ ]
        );
      };
      bridge = {
        wantedBy = map (unit: if pkgs.lib.hasSuffix ".target" unit then unit else "${unit}.target") (
          home.systemd.user.services.clipboard-bridge.Install.WantedBy or [ ]
        );
      };
      packageNames = map (pkg: (pkgs.lib.parseDrvName pkg.name).name) home.home.packages;
      binds = (mango.bind or [ ]) ++ (mango.key_mode.common.bindl or [ ]);
      configFiles = builtins.attrNames home.xdg.configFile;
      homeFiles = builtins.attrNames home.home.file;
      windowRules = mango.window_rule or [ ];
    }
  );
in
{
  mango-blur-sampling = import ./mango/blur-check.nix {
    inherit pkgs;
    mango = nixos.programs.mango.package;
  };

  # The Mango session owns the shell: Noctalia plus the polkit agent and the
  # X11 clipboard bridge are services on every session target, and no Mango
  # shell package (mangobar/mako/swayosd/fuzzel/swaylock/wallpaper daemons) is
  # installed any more. The generated Noctalia config, palette and Mango rule
  # table are read here so the visual contract is asserted, not just compared
  # as attribute names.
  unified-noctalia-session =
    pkgs.runCommand "unified-noctalia-session-check"
      {
        nativeBuildInputs = [ pkgs.python3 ];
        inherit metadata;
        PALETTE_FILE = home.xdg.configFile."noctalia/palettes/one-dark.json".source;
        NOCTALIA_CONFIG = home.xdg.configFile."noctalia/config.toml".source;
        MANGO_CONFIG = home.xdg.configFile."mango/config.conf".source;
        EXPECTED_ON_SURFACE = appearance.brightFg;
        EXPECTED_ON_SURFACE_VARIANT = appearance.fg;
        # The local hideclients plugin: manifest and the generated Luau entry.
        PLUGIN_MANIFEST = home.home.file.".local/share/noctalia/plugins/hideclients/plugin.toml".source;
        PLUGIN_ENTRY = home.home.file.".local/share/noctalia/plugins/hideclients/indicator.luau".source;
        EXPECTED_MMSG = "${nixos.programs.mango.package}/bin/mmsg";
      }
      ''
        python3 - "$metadata" <<'PY'
        import json, os, re, sys, tomllib

        data = json.load(open(sys.argv[1], "r", encoding="utf-8"))
        targets = set(data["targets"])
        errors = []

        def want(cond, message):
            if not cond:
                errors.append(message)

        want(set(data["graphicalSessionTargets"]) >= targets, "graphicalSessionTargets misses a session target")
        for name in ("noctalia", "polkit", "bridge"):
            want(set(data[name]["wantedBy"]) >= targets, f"{name} is not wanted by all session targets")
        want("noctalia" in data["packageNames"], "noctalia package is not installed")
        forbidden = {
            "mangobar", "mako", "swayosd", "fuzzel", "swaylock",
            "sweetbgd", "matuwall", "cliphist", "cliphist-tui", "wl-clip-persist",
            "umbriel", "luciole",
        }
        leftovers = forbidden.intersection(data["packageNames"])
        want(not leftovers, f"removed shell packages are still installed: {sorted(leftovers)}")
        binds = "\n".join(data["binds"])
        for marker in (
            "noctalia msg panel-toggle launcher",
            "noctalia msg panel-toggle clipboard",
            "noctalia msg panel-toggle session",
            "noctalia msg session lock",
            "noctalia msg screenshot-fullscreen",
            "noctalia msg volume-up",
            "noctalia msg brightness-up",
            "noctalia msg media toggle",
            "noctalia msg media stop",
            "noctalia msg media previous",
            "noctalia msg media next",
        ):
            want(marker in binds, f"missing bind marker: {marker}")
        want("SUPER+SHIFT,Escape,spawn," in binds, "Mango session panel bind is missing")
        want("playerctl" not in binds, "Mango still spawns playerctl for media keys")
        for marker in ("fuzzel", "cliphist", "swayosd-client", "wallpaper-pick", "screenshot-screen", "session-lock"):
            want(marker not in binds, f"stale shell bind: {marker}")
        want("noctalia/config.toml" in data["configFiles"], "Noctalia config file missing")
        want(
            "Pictures/Wallpapers/managed" in data["homeFiles"],
            "managed wallpaper link farm is not installed",
        )

        # Palette role semantics: body text is brightFg, secondary is fg.
        with open(os.environ["PALETTE_FILE"], "r", encoding="utf-8") as fh:
            palette = json.load(fh)["dark"]
        want(
            palette["on_surface"] == os.environ["EXPECTED_ON_SURFACE"],
            "palette on_surface is not the body (brightFg) token",
        )
        want(
            palette["on_surface_variant"] == os.environ["EXPECTED_ON_SURFACE_VARIANT"],
            "palette on_surface_variant is not the secondary (fg) token",
        )

        # Generated config: wallpaper browsing root, OSD corner, bar hierarchy.
        with open(os.environ["NOCTALIA_CONFIG"], "rb") as fh:
            config = tomllib.load(fh)
        want(
            config["wallpaper"]["directory"] == "~/Pictures/Wallpapers",
            "wallpaper panel directory is not the managed parent",
        )
        want(config["osd"]["position"] == "bottom_center", "OSD is not bottom_center")
        want(config["osd"]["offset_y"] == 48, "OSD offset_y is not 48")
        want(
            config["notification"].get("position", "top_right") == "top_right",
            "notification corner must stay top_right",
        )
        workspaces = config["widget"]["workspaces"]
        want(workspaces["occupied_color"] == "on_surface", "occupied workspaces must use on_surface")
        want(workspaces["empty_color"] == "on_surface_variant", "empty workspaces must use on_surface_variant")
        want("月" in config["widget"]["clock"]["format"], "bar clock lost its date")

        # Mango window rules: read the generated config (the parser's actual
        # input) and repeat the rule-table checks: 255-byte value limit, valid
        # regexes, then the Noctalia Settings resolution.
        with open(os.environ["MANGO_CONFIG"], "r", encoding="utf-8") as fh:
            rules = [
                line.split("=", 1)[1].strip()
                for line in fh
                if line.split("=", 1)[0].strip() == "window_rule"
            ]
        want(bool(rules), "Mango window rule table is empty")
        want(
            len(rules) == len(data["windowRules"]),
            "generated Mango config and settings disagree on the rule count",
        )
        rows = []
        for rule in rules:
            want(
                len(rule.encode()) <= 255,
                f"window rule exceeds the parser's 255-byte value limit: {rule}",
            )
            try:
                row = dict(field.strip().split(":", 1) for field in rule.split(","))
            except ValueError:
                want(False, f"window rule is not field:value list: {rule}")
                continue
            for key in ("app_id", "title"):
                if key in row:
                    try:
                        re.compile(row[key])
                    except re.error as exc:
                        want(False, f"invalid {key} regex in rule {rule}: {exc}")
            rows.append(row)

        def resolve(app, title):
            result = {}
            for row in rows:
                if all(
                    key not in row or re.search(row[key], value)
                    for key, value in (("app_id", app), ("title", title))
                ):
                    result.update(row)
            return result

        settings = resolve("dev.noctalia.Noctalia", "Noctalia Settings")
        want(settings.get("is_floating") == "1", "Noctalia Settings window is not floating")
        want(
            settings.get("width") == "1020" and settings.get("height") == "900",
            "Noctalia Settings window must float at 1020x900",
        )

        # Local Noctalia plugin restoring the mangobar-era minimized-client
        # counter: files installed, plugin enabled, widget placed on the bar,
        # and the Luau entry templated with a real mmsg path.
        for target in (
            ".local/share/noctalia/plugins/hideclients/plugin.toml",
            ".local/share/noctalia/plugins/hideclients/indicator.luau",
        ):
            want(target in data["homeFiles"], f"hideclients plugin file missing: {target}")
        want(
            "nix-dotfiles/hideclients" in config.get("plugins", {}).get("enabled", []),
            "hideclients plugin is not enabled in the generated config",
        )
        want(
            "hideclients" in config["bar"]["main"]["start"],
            "hideclients widget is not placed on the bar",
        )
        want(
            config["widget"]["hideclients"]["type"] == "nix-dotfiles/hideclients:indicator",
            "hideclients widget type is wrong",
        )
        with open(os.environ["PLUGIN_MANIFEST"], "rb") as fh:
            manifest = tomllib.load(fh)
        want(manifest.get("id") == "nix-dotfiles/hideclients", "plugin manifest id mismatch")
        want(manifest.get("plugin_api") == 3, "plugin manifest api level mismatch")
        want(
            any(entry.get("id") == "indicator" for entry in manifest.get("widget") or []),
            "plugin manifest has no indicator widget",
        )
        with open(os.environ["PLUGIN_ENTRY"], "r", encoding="utf-8") as fh:
            entry_text = fh.read()
        for placeholder in ("@mmsg@", "@mutedFg@"):
            want(placeholder not in entry_text, f"plugin entry keeps {placeholder}")
        want(
            os.environ["EXPECTED_MMSG"] in entry_text,
            "plugin entry has no absolute mmsg path",
        )

        if errors:
            print("\n".join(errors))
            sys.exit(1)
        print("unified Noctalia session contract ok")
        PY
        touch $out
      '';
}
