{
  pkgs,
  home,
  host,
  palette,
}:
let
  python = pkgs.python3.withPackages (p: [ p.tomlkit ]);
  # Use the host's generated fontconfig rules with an isolated home. This checks
  # family selection and missing-glyph fallback without applying the system.
  fontConfig = pkgs.makeFontsConf {
    fontDirectories = host.fonts.packages;
    impureFontDirectories = [ ];
    includes = [ "${host.environment.etc.fonts.source}/conf.d" ];
  };
  metadata = pkgs.writeText "desktop-contract.json" (
    builtins.toJSON {
      settings = home.programs.noctalia.settings;
      mango = home.wayland.windowManager.mango.settings;
      units = pkgs.lib.getAttrs [
        "noctalia"
        "fcitx5-daemon"
        "clipboard-bridge"
        "xrdb-merge"
      ] home.systemd.user.services;
      environment = home.systemd.user.sessionVariables;
      sharedTargets = home.nixDotfiles.graphicalSessionTargets;
      greeter = host.services.displayManager.noctalia-greeter.settings;
      boot = {
        inherit (host.boot) kernelParams;
        inherit (host.boot.loader) timeout;
        inherit (host.boot.loader.systemd-boot) consoleMode editor;
        initrdSystemd = host.boot.initrd.systemd.enable;
        initrdVerbose = host.boot.initrd.verbose;
        initrdModules = host.boot.initrd.kernelModules;
        initrdAvailableModules = host.boot.initrd.availableKernelModules;
        plymouth = {
          inherit (host.boot.plymouth) enable theme;
        };
        inherit (host.services.greetd) greeterManagesPlymouth;
        vt = host.services.greetd.settings.terminal.vt;
        greetdAfter = host.systemd.services.greetd.unitConfig.After;
      };
      console = {
        inherit (host.console) earlySetup font colors;
        ansi = import ../appearance/ansi.nix palette;
      };
      inherit palette;
    }
  );
  avatarMetadata = pkgs.writeText "avatar-contract.json" (
    builtins.toJSON {
      homeSource = builtins.toString home.xdg.dataFile."nix-dotfiles/mayon-avatar.png".source;
      hostSource = builtins.toString host.environment.etc."nix-dotfiles/mayon-avatar.png".source;
      sticker = home.programs.noctalia.settings.lockscreen_widgets.widget.lockscreen-widget-avatar;
    }
  );
  homeAvatarActivation = pkgs.writeText "seed-mayon-avatar.sh" home.home.activation.seedMayonAvatar.data;
  hostAvatarActivation = pkgs.writeText "accountsservice-mayon-avatar.sh" host.system.activationScripts.mayonAccountsServiceAvatar.text;
in
pkgs.runCommand "interactive-session-config"
  {
    nativeBuildInputs = [
      python
      pkgs.fontconfig
      pkgs.gawk
      pkgs.coreutils
    ];
  }
  ''
    export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/config" XDG_CACHE_HOME="$TMPDIR/cache" XDG_STATE_HOME="$TMPDIR/state" XDG_DATA_HOME="$TMPDIR/data"
    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$out"
    ${pkgs.lib.getExe home.programs.noctalia.package} config validate ${
      home.xdg.configFile."noctalia/config.toml".source
    } > "$out/noctalia.log" 2>&1 || { cat "$out/noctalia.log"; exit 1; }
    if grep -iE '\[WARN\]|warning:|\[ERROR\]|^WARN[[:space:]]|[1-9][0-9]* warning\(s\)' "$out/noctalia.log"; then exit 1; fi
    ${pkgs.lib.getExe home.wayland.windowManager.mango.package} -c ${
      home.xdg.configFile."mango/config.conf".source
    } -p > "$out/mango.log" 2>&1 || { cat "$out/mango.log"; exit 1; }
    if grep -iE 'conflict|unknown|invalid|error' "$out/mango.log"; then exit 1; fi
    # Retain the actual generated inputs beside the pinned parser logs.
    cp ${home.xdg.configFile."mango/config.conf".source} "$out/mango.conf"
    cp ${home.xdg.configFile."noctalia/config.toml".source} "$out/noctalia.toml"
    export FONTCONFIG_FILE=${fontConfig}
    fc-match -f '%{family}\n' sans-serif | tee "$out/sans-family.txt"
    grep -Fx '${palette.fonts.sans}' "$out/sans-family.txt"
    fc-match -f '%{family}\n' monospace | tee "$out/mono-family.txt"
    grep -Fx '${palette.fonts.mono}' "$out/mono-family.txt"
    fc-match -f '%{family}\n' '${palette.fonts.sans}:lang=zh-cn:charset=4e2d' | tee "$out/cjk-fallback.txt"
    grep -Fx '${palette.fonts.cjk}' "$out/cjk-fallback.txt"
    python3 ${./resources}/test_reconcile_overrides.py -v > "$out/ownership.log" 2>&1 || { cat "$out/ownership.log"; exit 1; }
    python3 - ${avatarMetadata} <<'PY'
    import json, sys
    from pathlib import Path
    data = json.load(open(sys.argv[1]))
    assert data["homeSource"] == data["hostSource"], data
    assert Path(data["homeSource"]).is_file()
    widget = data["sticker"]
    assert widget["type"] == "sticker", widget
    assert widget["box_width"] == 80.0 and widget["box_height"] == 80.0, widget
    assert widget["settings"]["image_path"] == "/home/mayon/.face", widget
    PY

    fixture="$TMPDIR/avatar-activation"
    mkdir -p "$fixture"
    run_home_activation() {
      local home_dir="$1" dry_run="''${2:-}"
      mkdir -p "$home_dir"
      sed "s|/home/mayon|$home_dir|g" ${homeAvatarActivation} > "$fixture/home-activation.sh"
      HOME="$home_dir" DRY_RUN="$dry_run" bash -c '
        run() { [ "''${DRY_RUN:-}" = 1 ] && return 0; "$@"; }
        source "$1"
      ' _ "$fixture/home-activation.sh"
    }
    data_home="$fixture/home/.local/share/nix-dotfiles"
    mkdir -p "$data_home"
    printf first-avatar > "$fixture/avatar-first.png"
    printf second-avatar > "$fixture/avatar-second.png"
    ln -s "$fixture/avatar-first.png" "$data_home/mayon-avatar.png"
    run_home_activation "$fixture/home"
    face="$fixture/home/.face"
    test -L "$face"
    test "$(readlink "$face")" = "$data_home/mayon-avatar.png"
    run_home_activation "$fixture/home"
    test "$(readlink "$face")" = "$data_home/mayon-avatar.png"
    ln -sfn "$fixture/avatar-second.png" "$data_home/mayon-avatar.png"
    test "$(cat "$face")" = second-avatar

    printf custom-regular > "$fixture/custom-regular"
    mkdir -p "$fixture/custom-home"
    cp "$fixture/custom-regular" "$fixture/custom-home/.face"
    cp "$fixture/custom-home/.face" "$fixture/custom-before"
    run_home_activation "$fixture/custom-home"
    cmp "$fixture/custom-before" "$fixture/custom-home/.face"

    mkdir -p "$fixture/custom-link-home"
    ln -s "$fixture/custom-regular" "$fixture/custom-link-home/.face"
    run_home_activation "$fixture/custom-link-home"
    test "$(readlink "$fixture/custom-link-home/.face")" = "$fixture/custom-regular"
    mkdir -p "$fixture/dangling-home"
    ln -s "$fixture/missing-custom-target" "$fixture/dangling-home/.face"
    run_home_activation "$fixture/dangling-home"
    test "$(readlink "$fixture/dangling-home/.face")" = "$fixture/missing-custom-target"
    mkdir -p "$fixture/dry-home"
    run_home_activation "$fixture/dry-home" 1
    test ! -e "$fixture/dry-home/.face" && test ! -L "$fixture/dry-home/.face"

    run_host_activation() {
      local accounts_root="$1"
      mkdir -p "$fixture"
      sed "s|/var/lib/AccountsService|$accounts_root|g" ${hostAvatarActivation} > "$fixture/host-activation.sh"
      bash "$fixture/host-activation.sh"
    }
    account_root="$fixture/AccountsService"
    icon_file="$account_root/icons/mayon"
    users_file="$account_root/users/mayon"
    run_host_activation "$account_root"
    test -L "$icon_file"
    test "$(readlink "$icon_file")" = /etc/nix-dotfiles/mayon-avatar.png
    grep -Fx "Icon=$icon_file" "$users_file" >/dev/null
    cp "$users_file" "$fixture/users-first"
    run_host_activation "$account_root"
    cmp "$fixture/users-first" "$users_file"

    printf custom-icon > "$fixture/custom-icon"
    rm "$icon_file"
    cp "$fixture/custom-icon" "$icon_file"
    run_host_activation "$account_root"
    cmp "$fixture/custom-icon" "$icon_file"
    rm "$icon_file"
    ln -s "$fixture/custom-icon" "$icon_file"
    run_host_activation "$account_root"
    test "$(readlink "$icon_file")" = "$fixture/custom-icon"

    rm "$users_file"
    cat > "$users_file" <<'INI'
    [Other]
    Name=keep-other
    [User]
    Name=Mayon
    INI
    run_host_activation "$account_root"
    test "$(grep -Fc '[User]' "$users_file")" = 1
    grep -Fx 'Name=keep-other' "$users_file" >/dev/null
    grep -Fx 'Name=Mayon' "$users_file" >/dev/null
    grep -Fx "Icon=$icon_file" "$users_file" >/dev/null

    printf '[User]\nName=Mayon\nIcon =    \n[Other]\nKeep=metadata\n' > "$users_file"
    run_host_activation "$account_root"
    test "$(grep -Fc '[User]' "$users_file")" = 1
    grep -Fx "Icon=$icon_file" "$users_file" >/dev/null
    grep -Fx 'Keep=metadata' "$users_file" >/dev/null

    printf '[Other]\nKeep=bytes\n[User]\nName=Mayon\nIcon = /custom/avatar with spaces.png\nNoFinalNewline=preserve' > "$users_file"
    cp "$users_file" "$fixture/custom-users-before"
    run_host_activation "$account_root"
    cmp "$fixture/custom-users-before" "$users_file"

    rm "$users_file"
    printf '[User]\nName=Mayon\n' > "$fixture/users-target"
    ln -s "$fixture/users-target" "$users_file"
    run_host_activation "$account_root"
    test "$(readlink "$users_file")" = "$fixture/users-target"
    grep -Fx 'Name=Mayon' "$fixture/users-target" >/dev/null
    ! grep -q '^Icon=' "$fixture/users-target"

    linked_root="$fixture/linked-root"
    mkdir -p "$fixture/real-accounts"
    ln -s "$fixture/real-accounts" "$linked_root"
    run_host_activation "$linked_root"
    test ! -e "$fixture/real-accounts/icons/mayon"

    icon_link_root="$fixture/icon-link-root"
    mkdir -p "$icon_link_root/AccountsService/users" "$fixture/real-icons"
    ln -s "$fixture/real-icons" "$icon_link_root/AccountsService/icons"
    run_host_activation "$icon_link_root/AccountsService"
    test ! -e "$fixture/real-icons/mayon"

    users_link_root="$fixture/users-link-root"
    mkdir -p "$users_link_root/AccountsService/icons" "$fixture/real-users"
    ln -s "$fixture/real-users" "$users_link_root/AccountsService/users"
    run_host_activation "$users_link_root/AccountsService"
    test ! -e "$users_link_root/AccountsService/icons/mayon"
    test ! -e "$fixture/real-users/mayon"

    python3 - ${metadata} ${
      home.xdg.configFile."noctalia/palettes/One-Dark-Darker.json".source
    } "$out/mango.conf" "$out/noctalia.toml" <<'PY'
    import json, re, sys, tomllib
    from pathlib import Path
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
    # Check serialized settings too: validating the Nix attrset alone would
    # miss a lost/renamed field during Home Manager's config generation.
    generated = tomllib.loads(Path(sys.argv[4]).read_text())
    expected = {
        ("shell", "launcher", "layout"): "full",
        ("shell", "launcher", "category_icons_only"): True,
        ("shell", "launcher", "track_usage"): True,
        ("shell", "launcher", "sort_by_usage"): True,
        ("shell", "launcher", "providers", "calculator", "global"): False,
        ("notification", "border_color"): "outline",
        ("notification", "border_width"): 1,
        ("osd", "border_color"): "outline",
        ("osd", "border_width"): 1,
        ("shell", "show_close_buttons"): False,
        ("theme", "sync_color_scheme"): False,
        ("shell", "panel", "border_color"): "outline",
        ("shell", "panel", "border_width"): 1,
        ("bar", "main", "show_tooltip"): True,
        ("widget", "workspaces", "style"): "regular",
        ("lockscreen_widgets", "widget", "lockscreen-login-box@eDP-1", "settings", "show_password_reveal"): True,
        ("lockscreen_widgets", "widget", "lockscreen-login-box@eDP-1", "settings", "input_radius"): 8.0,
    }
    for keys, value in expected.items():
        for root in (settings, generated):
            for key in keys:
                root = root[key]
            assert root == value, (keys, root, value)
    assert p["dark"]["mOutline"] == m["palette"]["border"]
    assert abs(settings["shell"]["corner_radius_scale"] - 4 / 3) < 1e-6
    assert settings["shell"]["corner_radius_scale"] == m["greeter"]["appearance"]["corner_radius_scale"]
    mango = m["mango"]
    # All 12 title_message_bar options must reach config.conf with the palette
    # mapping, not just be accepted by a parser that tolerates defaults.
    prefix = "title_message_bar_"
    title = {"height": 48, "gap": 12, "decorate_font_desc": m["palette"]["fonts"]["sans"] + " 10",
             "decorate_border_width": 1, "decorate_corner_radius": 8,
             "decorate_padding_x": 8, "decorate_padding_y": 4}
    for suffix, role in {"fg_color": "fg", "bg_color": "deep", "focus_fg_color": "black",
                         "focus_bg_color": "blue", "border_color": "border"}.items():
        title["decorate_" + suffix] = "0x" + m["palette"][role].removeprefix("#") + "ff"
    conf = Path(sys.argv[3]).read_text()
    parsed = {}
    for line in conf.splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1)
            parsed[key.strip()] = value.strip()
    for suffix, value in title.items():
        key = prefix + suffix
        assert mango[key] == value, (key, mango[key], value)
        assert parsed[key] == str(value), (key, parsed[key], value)
    assert {key for key in parsed if key.startswith(prefix)} == {prefix + key for key in title}
    for key, role, alpha in (("root_color", "bg", "ff"), ("drop_color", "blue", "80"), ("split_color", "cyan", "ff")):
        value = "0x" + m["palette"][role].removeprefix("#") + alpha
        assert mango[key] == parsed[key] == value, (key, value)
    assert mango["blur"] == mango["blur_layer"] == mango["layer_shadows"] == mango["layer_animations"] == 0
    assert settings["shell"]["panel"]["shadow"] and settings["bar"]["main"]["shadow"]
    assert mango["jump_label_decorate_corner_radius"] == mango["tab_bar_decorate_corner_radius"] == 8
    boot = m["boot"]
    assert boot["timeout"] == 1 and boot["consoleMode"] == "max" and not boot["editor"]
    assert boot["initrdSystemd"] and not boot["initrdVerbose"]
    assert "i915" in boot["initrdModules"]
    assert not any(name.startswith("nvidia") for name in boot["initrdModules"] + boot["initrdAvailableModules"])
    assert boot["plymouth"] == {"enable": True, "theme": "bgrt"}
    assert boot["vt"] == 1 and not boot["greeterManagesPlymouth"]
    assert "plymouth-quit-wait.service" in boot["greetdAfter"]
    assert {"splash", "quiet", "udev.log_level=3", "systemd.show_status=auto"} <= set(boot["kernelParams"])
    assert not {"rd.udev.log_level=3", "rd.systemd.show_status=auto"} & set(boot["kernelParams"])
    assert m["console"]["earlySetup"] and m["console"]["font"] == "ter-v32n"
    assert m["console"]["colors"] == [color.removeprefix("#") for color in m["console"]["ansi"]]
    wallpaper = settings["wallpaper"]
    directory = Path(wallpaper["directory"])
    assert sorted(path.name for path in directory.iterdir()) == [f"wallpaper-{n}.png" for n in ("002", "005", "008", "009", "011")]
    assert all(path.is_symlink() and path.is_file() for path in directory.iterdir())
    assert wallpaper["automation"] == {"enabled": True, "order": "random", "interval_seconds": 86400, "recursive": False}
    default = directory / "wallpaper-005.png"
    assert Path(wallpaper["default"]["path"]).resolve() == default.resolve()
    assert Path(m["greeter"]["appearance"]["wallpaper"]["path"]).resolve() == default.resolve()
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
