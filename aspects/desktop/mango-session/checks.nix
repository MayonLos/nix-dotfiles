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
        "umbriel-session.target"
        "hyprland-session.target"
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
    }
  );
in
{
  mango-blur-sampling = import ./mango/blur-check.nix {
    inherit pkgs;
    mango = nixos.programs.mango.package;
  };

  # The three sessions share one shell: Noctalia plus the polkit agent and the
  # X11 clipboard bridge are services on every session target, and no Mango
  # shell package (mangobar/mako/swayosd/fuzzel/swaylock/wallpaper daemons) is
  # installed any more.
  unified-noctalia-session =
    pkgs.runCommand "unified-noctalia-session-check"
      {
        nativeBuildInputs = [ pkgs.python3 ];
        inherit metadata;
      }
      ''
        python3 - "$metadata" <<'PY'
        import json, sys
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
        }
        leftovers = forbidden.intersection(data["packageNames"])
        want(not leftovers, f"removed shell packages are still installed: {sorted(leftovers)}")
        binds = "\n".join(data["binds"])
        for marker in (
            "noctalia msg panel-toggle launcher",
            "noctalia msg panel-toggle clipboard",
            "noctalia msg session lock",
            "noctalia msg screenshot-fullscreen",
            "noctalia msg volume-up",
            "noctalia msg brightness-up",
        ):
            want(marker in binds, f"missing bind marker: {marker}")
        for marker in ("fuzzel", "cliphist", "swayosd-client", "wallpaper-pick", "screenshot-screen", "session-lock"):
            want(marker not in binds, f"stale shell bind: {marker}")
        want("noctalia/config.toml" in data["configFiles"], "Noctalia config file missing")
        if errors:
            print("\n".join(errors))
            sys.exit(1)
        print("unified Noctalia session contract ok")
        PY
        touch $out
      '';
}
