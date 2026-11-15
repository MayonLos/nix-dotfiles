{
  pkgs,
  home,
  host,
  palette,
}:
let
  wallpapers = import ../../appearance/appearance/resources/wallpaper/package.nix {
    inherit pkgs palette;
  };
  python = pkgs.python3.withPackages (p: [ p.tomlkit ]);
  localPlugins =
    (pkgs.lib.findFirst (
      source: source.name == "nix-dotfiles"
    ) null home.programs.noctalia.settings.plugins.source).location;
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
      noctaliaPatches = map (path: {
        name = builtins.baseNameOf path;
        content = builtins.readFile path;
      }) home.programs.noctalia.package.patches;
      wallpaperAssets = map (item: {
        inherit (item) name;
        path = "${item.path}";
      }) wallpapers.wallpapers;
      wallpaperFactoryDefault = toString wallpapers.default;
      wallpaperManagedSource = toString home.home.file."Pictures/Wallpapers/managed".source;
      wallpaperRoot = "${home.home.homeDirectory}/Pictures/Wallpapers";
      wallpaperActivation = home.home.activation.wallpaperLocalDirectory.data;
      mango = home.wayland.windowManager.mango.settings;
      mangoPatches = map (path: {
        name = builtins.baseNameOf path;
        content = builtins.readFile path;
      }) home.wayland.windowManager.mango.package.patches;
      mangoSessionVariables = home.wayland.windowManager.mango.systemd.variables;
      units = pkgs.lib.getAttrs [
        "noctalia"
        "fcitx5-daemon"
        "clipboard-bridge"
        "xrdb-merge"
        "mangobar"
        "mako"
        "swayosd"
        "cliphist"
        "cliphist-images"
        "wl-clip-persist"
      ] home.systemd.user.services;
      mangobar = home.services.mangobar.settings;
      mangobarStyle = home.xdg.configFile."mangobar/style.css".text;
      # The poll script is a store path; the checker reads it after the build.
      mangobarBluetoothScript = home.services.mangobar.settings."custom/bluetooth".exec;
      mangobarPatches = map (path: {
        name = builtins.baseNameOf path;
        content = builtins.readFile path;
      }) home.services.mangobar.package.patches;
      fuzzel = home.programs.fuzzel.settings;
      mako = home.services.mako.settings;
      # Store path, read by the checker after the package is built.
      makoPackage = "${home.services.mako.package}";
      makoDbusService = home.xdg.dataFile."dbus-1/services/org.freedesktop.Notifications.service".text;
      swayosd = {
        topMargin = home.services.swayosd.topMargin;
        # A store path, read by the checker after the stylesheet is built.
        # readFile here would import the derivation during evaluation.
        style = "${home.services.swayosd.stylePath}";
      };
      swayosdConfig = home.xdg.configFile."swayosd/config.toml".text;
      swayosdBackend = {
        wantedBy = host.systemd.services.swayosd-libinput-backend.wantedBy;
        execStart = host.systemd.services.swayosd-libinput-backend.serviceConfig.ExecStart;
        restart = host.systemd.services.swayosd-libinput-backend.serviceConfig.Restart;
      };
      swayosdSystemBusPolicy = builtins.any (
        pkg: (pkg.pname or "") == "swayosd"
      ) host.services.dbus.packages;
      swayosdPolkit = host.security.polkit.extraConfig;
      videoGroup = builtins.elem "video" host.users.users.mayon.extraGroups;
      swayosdUdev = builtins.any (pkg: (pkg.pname or "") == "swayosd") host.services.udev.packages;
      environment = home.systemd.user.sessionVariables;
      shellEnvironment = home.home.sessionVariables;
      fcitxClassicUI = home.i18n.inputMethod.fcitx5.settings.addons.classicui.globalSection;
      sharedTargets = home.nixDotfiles.graphicalSessionTargets;
      greeter = {
        command = host.services.greetd.settings.default_session.command;
        environments = host.environment.etc."greetd/environments".text;
        css = host.environment.etc."greetd/gtkgreet.css".text;
        sway = host.environment.etc."greetd/sway.conf".text;
      };
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
        ansi = import ../../appearance/appearance/ansi.nix palette;
      };
      inherit palette;
    }
  );
  avatarMetadata = pkgs.writeText "avatar-contract.json" (
    builtins.toJSON {
      homeSource = builtins.toString home.xdg.dataFile."nix-dotfiles/mayon-avatar.png".source;
      hostSource = builtins.toString host.environment.etc."nix-dotfiles/mayon-avatar.png".source;
      widgets = builtins.attrNames home.programs.noctalia.settings.lockscreen_widgets.widget;
    }
  );
  homeAvatarActivation = pkgs.writeText "seed-mayon-avatar.sh" home.home.activation.seedMayonAvatar.data;
  hostAvatarActivation = pkgs.writeText "accountsservice-mayon-avatar.sh" host.system.activationScripts.mayonAccountsServiceAvatar.text;
in
assert home.wayland.windowManager.mango.package == host.programs.mango.package;
pkgs.runCommand "interactive-session-config"
  {
    nativeBuildInputs = [
      python
      pkgs.fontconfig
      pkgs.gawk
      pkgs.coreutils
      pkgs.imagemagick
      pkgs.lua
    ];
  }
  ''
    export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/config" XDG_CACHE_HOME="$TMPDIR/cache" XDG_STATE_HOME="$TMPDIR/state" XDG_DATA_HOME="$TMPDIR/data"
    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$out"
    ${pkgs.lib.getExe home.programs.noctalia.package} config validate ${
      home.xdg.configFile."noctalia/config.toml".source
    } > "$out/noctalia.log" 2>&1 || { cat "$out/noctalia.log"; exit 1; }
    if grep -iE '\[WARN\]|warning:|\[ERROR\]|^WARN[[:space:]]|[1-9][0-9]* warning\(s\)' "$out/noctalia.log"; then exit 1; fi
    ${pkgs.lib.getExe home.programs.noctalia.package} plugins lint ${localPlugins} > "$out/plugins.log" 2>&1 || { cat "$out/plugins.log"; exit 1; }
    python3 - ${./resources/noctalia-plugins/launchpad/plugin.toml} <<'PY'
    import sys, tomllib
    manifest = tomllib.load(open(sys.argv[1], "rb"))
    layer = manifest["layer"][0]
    assert layer["output"] == "focused" and layer["keyboard"] == "exclusive"
    assert layer["layer"] == "overlay" and layer["exclusive_zone"] == -1
    assert set(layer["anchors"]) == {"top", "bottom", "left", "right"}
    assert {"Escape", "Return", "Super+a", "Page_Up", "Page_Down"} <= set(layer["capture_keys"])
    PY
    lua ${./resources/test-desktop-menus.lua} ${./resources/noctalia-plugins/desktop-menus} > "$out/desktop-menus.log"
    ${pkgs.lua5_4}/bin/lua ${./resources/test-launchpad.lua} ${localPlugins}/launchpad > "$out/launchpad.log"
    lua ${./resources/test-conservation.lua} ${./resources/noctalia-plugins/legion-conservation/status.luau} > "$out/conservation.log"
    ${pkgs.lib.getExe home.wayland.windowManager.mango.package} -c ${
      home.xdg.configFile."mango/config.conf".source
    } -p > "$out/mango.log" 2>&1 || { cat "$out/mango.log"; exit 1; }
    if grep -iE 'conflict|unknown|invalid|error' "$out/mango.log"; then exit 1; fi
    # Retain the actual generated inputs beside the pinned parser logs.
    cp ${home.xdg.configFile."mango/config.conf".source} "$out/mango.conf"
    cp ${home.xdg.configFile."noctalia/config.toml".source} "$out/noctalia.toml"
    python3 ${./resources/window-rules-check.py} "$out/mango.conf"
    python3 ${./mango/check-window-rules.py} "$out/mango.conf" > "$out/window-rules.log"
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
    assert "lockscreen-widget-avatar" not in data["widgets"]
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
      home.xdg.configFile."noctalia/palettes/onedark.json".source
    } "$out/mango.conf" "$out/noctalia.toml" "$out" <<'PY'
    import json, os, re, shutil, subprocess, sys, tomllib
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
    assert p["dark"]["mSurface"] == m["palette"]["bg"]
    settings = m["settings"]
    patches = {patch["name"]: patch["content"] for patch in m["noctaliaPatches"]}
    assert set(patches) == {"astra-selection.patch", "tech-lockscreen.patch", "nvidia-sampler.patch", "active-app-name.patch", "launchpad-native.patch", "desktop-menus.patch", "r43-control-center.patch", "r43-notifications.patch", "r43-osd.patch", "r43-calendar.patch", "r43-settings.patch", "r43-wallpaper.patch", "r44-status-icons.patch", "r50-panel-widths.patch"}
    for name, marker in {"astra-selection.patch": "syncCompactControls", "tech-lockscreen.patch": "m_identityAvatar->setRadius(28.0F)", "nvidia-sampler.patch": "gpuOnlyNvidia", "active-app-name.patch": "resolveRunningDesktopEntry", "launchpad-native.patch": "provider.activate(result)", "desktop-menus.patch": "workspaceWindowAssignments(it->output)"}.items():
        assert marker in patches[name], name
    # Check serialized settings too: validating the Nix attrset alone would
    # miss a lost/renamed field during Home Manager's config generation.
    generated = tomllib.loads(Path(sys.argv[4]).read_text())
    expected = {
        ("shell", "launcher", "layout"): "full",
        ("shell", "launcher", "width"): 520,
        ("shell", "launcher", "category_icons_only"): True,
        ("shell", "app_icon_colorize"): False,
        ("control_center", "sidebar"): "none",
        ("control_center", "sidebar_section"): "compact",
        ("control_center", "width"): 360,
        ("notification", "width"): 360,
        ("notification", "offset_x"): 28,
        ("notification", "offset_y"): 24,
        ("shell", "animation", "enabled"): not m["palette"]["reducedMotion"],
        ("shell", "animation", "speed"): 1.0,
        ("nightlight", "enabled"): False,
        ("nightlight", "force"): False,
        ("shell", "panel", "transparency_mode"): "soft",
        ("notification", "background_opacity"): 1.0,
        ("osd", "background_opacity"): 0.80,
        ("bar", "main", "thickness"): 30,
        ("bar", "main", "radius"): 0,
        ("bar", "main", "margin_ends"): 0,
        ("bar", "main", "margin_edge"): 0,
        ("bar", "main", "font_family"): "Inter",
        ("bar", "main", "font_weight"): 500,
        ("bar", "main", "font_scale"): 0.93,
        ("bar", "main", "background_opacity"): 0.62,
        ("bar", "main", "compositor_blur"): True,
        ("bar", "main", "border_width"): 0,
        ("bar", "main", "shadow"): False,
        ("bar", "main", "contact_shadow"): False,
        ("bar", "main", "capsule"): False,
        ("widget", "launcher", "custom_image_colorize"): True,
        ("widget", "active_window", "display"): "text_only",
        ("widget", "active_window", "show_app_name"): True,
        ("widget", "active_window", "font_weight"): 650,
        ("widget", "control-center", "glyph"): "adjustments-horizontal",
        ("widget", "clock", "format"): "{:%m月%d日 周%a %H:%M}",
        ("shell", "screen_corners", "enabled"): False,
        ("widget", "workspaces", "style"): "minimal",
        ("widget", "workspaces", "show_labels"): True,
        ("widget", "workspaces", "show_icons"): False,
        ("widget", "workspaces", "capsule"): False,
        ("widget", "workspaces", "active_dot"): True,
        ("widget", "workspaces", "hover_preview"): True,
        ("widget", "workspaces", "font_weight"): 600,
        ("widget", "workspaces", "occupied_color"): m["palette"]["muted"],
        ("widget", "workspaces", "change_color_on_hover"): True,
        ("widget", "launcher", "actions", "left"): "panel-toggle nix-dotfiles/desktop-menus:system",
        ("widget", "workspaces", "hide_when_empty"): True,
        ("widget", "workspaces", "focused_output_only"): False,
        ("widget", "workspaces", "focused_color"): m["palette"]["brightFg"],
        ("widget", "battery", "display_mode"): "glyph",
        ("widget", "battery", "show_label"): True,
        ("widget", "battery", "label_content"): "percent",
        ("widget", "battery", "actions", "left"): "exec legion-conservation toggle",
        ("widget", "tray", "drawer"): False,
        ("widget", "tray", "pinned"): ["fcitx"],
        ("widget", "notifications", "hide_when_no_unread"): True,
        ("system", "monitor", "gpu_poll_seconds"): 2.0,
        ("system", "monitor", "gpu_only_nvidia"): True,
        ("dock", "enabled"): True,
        ("dock", "position"): "bottom",
        ("dock", "smart_auto_hide"): True,
        ("dock", "auto_hide"): False,
        ("dock", "reserve_space"): False,
        ("dock", "layer"): "top",
        ("dock", "show_running"): True,
        ("dock", "show_dots"): True,
        ("dock", "launcher_position"): "start",
        ("dock", "margin_edge"): 8,
        ("dock", "radius"): 16,
        ("dock", "shadow"): False,
        ("dock", "background_opacity"): 0.80,
        ("dock", "compositor_blur"): True,
        ("dock", "pinned"): ["kitty", "firefox", "obsidian", "thunar", "code", "qq", "musicfox"],
        ("shell", "launcher", "default_view"): "pinned",
        ("shell", "launcher", "track_usage"): True,
        ("shell", "launcher", "sort_by_usage"): True,
        ("shell", "launcher", "pinned"): ["kitty", "nvim", "firefox", "thunar"],
        ("shell", "launcher", "providers", "calculator", "global"): False,
        ("notification", "border_color"): "outline_variant",
        ("notification", "border_width"): 1,
        ("osd", "border_color"): "outline_variant",
        ("osd", "border_width"): 1,
        ("osd", "offset_y"): 96,
        ("shell", "show_close_buttons"): False,
        ("shell", "settings_window_translucent"): True,
        ("theme", "sync_color_scheme"): False,
        ("shell", "panel", "border_color"): "outline_variant",
        ("shell", "panel", "border_width"): 1,
        ("shell", "panel", "shadow"): False,
        ("shell", "panel", "wallpaper_placement"): "floating",
        ("shell", "panel", "wallpaper_position"): "center",
        ("bar", "main", "show_tooltip"): True,
        ("lockscreen_widgets", "widget", "lockscreen-login-box@eDP-1", "settings", "show_password_reveal"): True,
        ("lockscreen_widgets", "widget", "lockscreen-login-box@eDP-1", "settings", "input_radius"): 8.0,
    }
    for keys, value in expected.items():
        for root in (settings, generated):
            for key in keys:
                root = root[key]
            assert root == value, (keys, root, value)
    for root in (settings, generated):
        assert root["bar"]["main"]["enabled"] is False
        assert root["shell"]["clipboard_enabled"] is False
        assert root["notification"]["enable_daemon"] is False
        assert root["osd"]["enabled"] is False
        corner = root["hot_corners"]["bottom_left"]
        assert corner["action"] == "command" and str(corner["command"]).endswith("/bin/fuzzel")
        bar = root["bar"]["main"]
        assert bar["start"] == ["launcher", "active_window", "workspaces"]
        assert bar["center"] == []
        assert bar["end"] == ["tray", "network", "bluetooth", "battery", "notifications", "control-center", "clock"]
        assert not bar.get("capsule_group")
        assert not any(name.startswith(("monitor-", "separator-", "group:")) for name in root["widget"])
        assert root["battery"]["warning_threshold"] == 20
        assert root["dock"]["magnification_scale"] <= 1.25
        assert [item["type"] for item in root["control_center"]["shortcuts"]] == ["wifi", "clash", "bluetooth", "notification"]
        assert root["notification"]["offset_y"] == 24
    assert "battery-charging" in patches["r44-status-icons.patch"]
    assert settings["bar"]["main"]["icon_color"] == m["palette"]["brightFg"]
    for name in ("network", "bluetooth", "battery", "tray", "notifications", "control-center"):
        assert settings["widget"][name]["scale"] == 1.125
    assert "workspaces_widget" not in patches["astra-selection.patch"]
    local_ids = {"nix-dotfiles/legion-conservation", "nix-dotfiles/launchpad", "nix-dotfiles/desktop-menus"}
    for root in (settings, generated):
        assert set(root["plugins"]["enabled"]) == local_ids
        assert len(root["plugins"]["enabled"]) == len(local_ids)
        assert [source["name"] for source in root["plugins"]["source"]] == ["nix-dotfiles"]
        assert set(root["plugin_settings"]) <= local_ids
        assert root["shell"]["launcher"]["providers"] == {"calculator": {"global": False}}
        assert not any("/" in name and not name.startswith("nix-dotfiles/") for name in root["widget"])
    assert {"base", "draw", "math", "startcenter", "rofi", "xterm", "thunar-bulk-rename", "thunar-volman-settings", "org.fcitx.Fcitx5"} <= set(settings["plugin_settings"]["nix-dotfiles/launchpad"]["hidden_apps"])
    icon_overrides = settings["plugin_settings"]["nix-dotfiles/launchpad"]["icon_overrides"]
    assert {entry.split("=", 1)[0] for entry in icon_overrides} == {"nvim", "workspace-task-terminal", "Dead by Daylight"}
    for entry in icon_overrides:
        assert Path(entry.split("=", 1)[1]).is_file(), entry
    assert p["dark"]["mOutline"] == m["palette"]["border"]
    assert abs(settings["shell"]["corner_radius_scale"] - 4 / 3) < 1e-6
    mango = m["mango"]
    # All 12 title_message_bar options must reach config.conf with the palette
    # mapping, not just be accepted by a parser that tolerates defaults.
    prefix = "title_message_bar_"
    title = {"height": 48, "gap": 12, "decorate_font_desc": m["palette"]["fonts"]["mono"] + " 10.5",
             "decorate_border_width": 1, "decorate_corner_radius": 8,
             "decorate_padding_x": 8, "decorate_padding_y": 4}
    for suffix, role in {"fg_color": "fg", "bg_color": "deep", "focus_fg_color": "blue",
                         "focus_bg_color": "selection", "border_color": "border"}.items():
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
    center_patch = next(p for p in m["mangoPatches"] if p["name"] == "r52-center-rule-sized-floats.patch")
    assert "!c->iscustomsize" in center_patch["content"]
    assert "c->iscustomsize || !client_is_x11(c)" in center_patch["content"]
    assert mango["blur"] == mango["blur_layer"] == 1
    assert mango["layer_shadows"] == mango["layer_animations"] == 0
    assert mango["blur_optimized"] == 1
    assert mango["layer_rule"][:2] == ["layer_name:.*,no_blur:1", "layer_name:^noctalia-(bar-.*|dock)$,no_blur:0,no_animation:1,no_shadow:1"]
    assert "noctalia-system-menu" in mango["layer_rule"][2]
    assert mango["layer_rule"][3] == "layer_name:^noctalia-plugin:nix-dotfiles/launchpad:drawer$,no_blur:0,no_animation:1,no_shadow:1"
    assert mango["layer_rule"][4] == "layer_name:^noctalia-(panel|attached-panel|osd)$,no_animation:1,no_blur:0,no_shadow:1"
    assert mango["layer_rule"][5] == "layer_name:^noctalia-notification$,no_animation:1,no_blur:1,no_shadow:1"
    assert mango["layer_rule"][-3:] == [
        "layer_name:^mangobar$,no_blur:1,no_animation:1,no_shadow:1",
        "layer_name:^notifications$,no_animation:1,no_blur:1,no_shadow:1",
        "layer_name:^swayosd$,no_animation:1,no_blur:1,no_shadow:1",
    ]
    assert mango["zoom_initial_ratio"] == 0.92 and mango["zoom_end_ratio"] == 0.92
    assert mango["fade_in_begin_opacity"] == 0 and mango["fade_out_begin_opacity"] == 1
    assert mango["animation_type_open"] == mango["animation_type_close"] == "zoom"
    assert "tech-osd-segments.patch" not in patches
    assert "SUPER,A,spawn,noctalia msg plugin nix-dotfiles/launchpad:control all toggle" in mango["bind"]
    assert "ALT,space,spawn,fuzzel" in mango["bind"]
    assert "SUPER,V,spawn,clipboard-history" in mango["bind"]
    hardware = mango["key_mode"]["common"]["bindl"]
    assert "NONE,XF86AudioRaiseVolume,spawn,swayosd-client --output-volume raise" in hardware
    assert "NONE,XF86AudioLowerVolume,spawn,swayosd-client --output-volume lower" in hardware
    assert "NONE,XF86AudioMute,spawn,swayosd-client --output-volume mute-toggle" in hardware
    assert "NONE,XF86MonBrightnessUp,spawn,swayosd-client --brightness raise" in hardware
    assert "NONE,XF86MonBrightnessDown,spawn,swayosd-client --brightness lower" in hardware
    assert "NONE,XF86AudioMicMute,spawn,noctalia msg mic-mute" in hardware
    assert not any("panel-toggle launcher" in binding or "panel-toggle clipboard" in binding for binding in mango["bind"])
    assert not any(
        token in binding
        for binding in list(mango["bind"]) + list(hardware)
        for token in ("volume-up", "volume-down", "volume-mute", "brightness-up", "brightness-down")
    )
    assert "ALT,Tab,spawn,noctalia msg window-switcher hold" in mango["bind"]
    assert "force_tearing:0,no_blur:1,app_id:.*" in mango["window_rule"]
    assert mango["window_rule"][-1] == "no_blur:0,app_id:^dev[.]noctalia[.]Noctalia$"
    assert not any(binding.startswith("SUPER+CTRL,W,") for binding in mango["bind"])
    assert not any(binding.startswith(("SUPER+SHIFT,X,", "SUPER+CTRL,P,", "SUPER+SHIFT,Y,", "SUPER+SHIFT,F1,", "SUPER+SHIFT,V,", "SUPER+SHIFT,F10,", "SUPER+SHIFT,F11,", "SUPER+SHIFT,F12,")) for binding in mango["bind"])
    assert "SUPER+SHIFT,T,switcher,next" in mango["bind"]
    for chord, scratch, tool in (("SUPER+SHIFT,D,", "mayon-tools", "mayon-tools"), ("SUPER+SHIFT,B,", "mayon-bili", "bilitui-mayon")):
        matches = [binding for binding in mango["bind"] if binding.startswith(chord)]
        assert len(matches) == 1 and "noctalia" not in matches[0]
        assert f"toggle_named_scratchpad,{scratch}," in matches[0] and f"--class={scratch} " in matches[0]
        assert matches[0].split()[-1].endswith(tool)
    voice = [binding for binding in mango["bindr"] if binding.startswith("SUPER+SHIFT,XF86Assistant,")]
    assert len(voice) == 1 and voice[0].endswith("/bin/mayon-voice toggle")
    assert not any("XF86Assistant" in binding for binding in mango["bind"])
    assert "SUPER,R,setkeymode,resize" in mango["bind"]
    assert not settings["shell"]["panel"]["shadow"] and not settings["bar"]["main"]["shadow"]
    assert mango["border_px"] == 2 and mango["border_radius"] == 16
    assert mango["border_color"] == "0x" + m["palette"]["border"].removeprefix("#") + "ff"
    assert mango["focus_color"] == "0x" + m["palette"]["blue"].removeprefix("#") + "ff"
    assert mango["gap_inner_horizontal"] == mango["gap_inner_vertical"] == 10
    assert mango["gap_outer_horizontal"] == mango["gap_outer_vertical"] == 16
    # One window keeps the same gap/border/radius as several windows; only
    # monocle (a full-screen stack) drops its frame.
    assert mango["smart_gaps"] == mango["no_border_when_single"] == mango["no_radius_when_single"] == 0
    assert mango["monocle_no_border"] == mango["monocle_no_gap"] == mango["monocle_no_radius"] == 1
    assert mango["overview_gap_inner"] == 12 and mango["overview_gap_outer"] == 24
    assert mango["overcircle_center_ratio"] == 0.68
    assert mango["shadows_position_x"] == 0 and mango["shadows_position_y"] == 10
    assert mango["shadows_size"] == 18 and mango["shadows_blur"] == 32
    assert mango["shadows_color"] == "0x" + m["palette"]["black"].removeprefix("#") + "66"
    assert mango["shadow_only_floating"] == 1 and "focused_shadows_color" not in mango
    assert mango["dim_enable"] == 1
    assert mango["dim_focused_color"] == "0x" + m["palette"]["black"].removeprefix("#") + "00"
    assert mango["dim_unfocused_color"] == "0x" + m["palette"]["black"].removeprefix("#") + "18"
    assert mango["focus_on_activate"] == 0
    assert mango["allow_tearing"] == 2
    assert mango["animations"] == (0 if m["palette"]["reducedMotion"] else 1)
    for event, duration in {"open": 220, "close": 180, "move": 180, "tag": 280, "focus": 120}.items():
        assert mango["animation_duration_" + event] == duration
        assert mango["animation_curve_" + event] == "0.16,1.0,0.3,1.0"
    assert m["fcitxClassicUI"]["PreferTextIcon"] == "True"
    assert "keyboard_layout" not in settings["bar"]["main"]["end"]
    assert m["environment"]["XCURSOR_THEME"] == m["palette"]["cursor"]["name"]
    assert m["environment"]["XCURSOR_SIZE"] == str(m["palette"]["cursor"]["size"])
    assert m["palette"]["cursor"] == {"name": "Bibata-Modern-Ice", "size": 24}
    assert m["mango"]["cursor_theme"] == m["palette"]["cursor"]["name"]
    assert m["mango"]["cursor_size"] == 24
    for prefix in ("tab_bar_decorate_", "group_bar_decorate_", "jump_label_decorate_"):
        assert mango[prefix + "focus_fg_color"] == "0x" + m["palette"]["blue"].removeprefix("#") + "ff"
        assert mango[prefix + "focus_bg_color"] == "0x" + m["palette"]["selection"].removeprefix("#") + "ff"
    assert mango["tab_bar_height"] == mango["group_bar_height"] == 32
    for prefix in ("tab_bar_decorate_", "group_bar_decorate_"):
        assert mango[prefix + "font_desc"] == m["palette"]["fonts"]["mono"] + " 10.5"
        assert mango[prefix + "padding_x"] == 8 and mango[prefix + "padding_y"] == 4
        assert mango[prefix + "corner_radius"] == 8 and mango[prefix + "border_width"] == 1
    assert mango["jump_label_decorate_font_desc"] == m["palette"]["fonts"]["mono"] + " Bold 12"
    assert mango["jump_label_decorate_bg_color"] == "0x" + m["palette"]["deep"].removeprefix("#") + "ff"
    assert mango["jump_label_decorate_fg_color"] == "0x" + m["palette"]["brightFg"].removeprefix("#") + "ff"
    assert mango["jump_label_decorate_padding_x"] == 8 and mango["jump_label_decorate_padding_y"] == 4
    assert mango["jump_label_decorate_border_width"] == 1
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
    wallpaper_root = Path(m["wallpaperRoot"])
    assert directory == wallpaper_root
    assert wallpaper["automation"] == {"enabled": True, "order": "random", "interval_seconds": 86400, "recursive": True, "pause_on_fullscreen": True}
    managed_source = Path(m["wallpaperManagedSource"])
    expected_names = sorted(["wallpaper-001.jpg", "wallpaper-002.jpg"] + [f"wallpaper-{n:03d}.png" for n in range(3, 19)])
    assert sorted(asset["name"] for asset in m["wallpaperAssets"]) == expected_names
    assert sorted(path.name for path in managed_source.iterdir()) == expected_names
    assert all(path.is_symlink() and path.is_file() for path in managed_source.iterdir())
    assert Path(wallpaper["default"]["path"]).resolve() == Path(m["wallpaperFactoryDefault"]).resolve()
    greeter_wallpaper = re.search(r'url\("file://(/nix/store/[^"]+)"\)', m["greeter"]["css"])
    assert greeter_wallpaper and Path(greeter_wallpaper.group(1)).is_file()
    assert "background-size: cover" in m["greeter"]["css"]
    assert all(Path(asset["path"]).is_file() for asset in m["wallpaperAssets"])
    activation = m["wallpaperActivation"]
    local_path = str(wallpaper_root / "local")
    assert activation.count(local_path) == 1
    assert not re.search(r"\b(rm|cp|mv|ln|install)\b", activation)
    fixture_root = Path(sys.argv[5]) / "wallpaper-activation"
    fixture_local = fixture_root / "Pictures" / "Wallpapers" / "local"
    activation = activation.replace(local_path, str(fixture_local))
    activation_script = Path(sys.argv[5]) / "wallpaper-local-activation.sh"
    activation_script.write_text(activation)
    def run_wallpaper_activation():
        return subprocess.run(
            ["bash", "-e", "-c", 'run() { "$@"; }; source "$1"', "wallpaper-test", str(activation_script)],
            text=True, capture_output=True,
        )
    try:
        assert run_wallpaper_activation().returncode == 0
        sentinel = fixture_local / "keep.png"
        sentinel.write_text("user-owned")
        assert run_wallpaper_activation().returncode == 0
        assert sentinel.read_text() == "user-owned"
        linked_target = fixture_root / "preserved-target"
        linked_target.mkdir()
        (linked_target / "marker").write_text("keep")
        shutil.rmtree(fixture_local)
        fixture_local.symlink_to(linked_target, target_is_directory=True)
        assert run_wallpaper_activation().returncode == 0
        assert (linked_target / "marker").read_text() == "keep"
        fixture_local.unlink()
        fixture_local.write_text("preserve-file")
        rejected = run_wallpaper_activation()
        assert rejected.returncode != 0 and fixture_local.read_text() == "preserve-file"
    finally:
        shutil.rmtree(fixture_root, ignore_errors=True)
    assert settings["theme"]["source"] == "custom" and settings["theme"]["mode"] == "dark"
    assert settings["theme"]["custom_palette"] == "onedark"
    assert "kitty" not in settings["theme"]["templates"]["builtin_ids"]
    assert "mango" not in settings["theme"]["templates"]["builtin_ids"]
    assert "btop" not in settings["theme"]["templates"]["builtin_ids"]
    widgets = settings["lockscreen_widgets"]["widget"]
    assert widgets["lockscreen-widget-clock"]["settings"]["format"] == "{:%H:%M}"
    assert widgets["lockscreen-widget-date"]["settings"]["format"] == "{:%-m月%-d日 %A}"
    assert "lockscreen-widget-seconds" not in widgets
    assert "lockscreen-widget-seconds" not in settings["lockscreen_widgets"]["widget_order"]
    for name in ("clock", "date"):
        assert widgets["lockscreen-widget-" + name]["settings"]["font_family"] == m["palette"]["fonts"]["sans"]
    assert settings["lockscreen"]["blur_intensity"] == 0.75
    assert settings["lockscreen"]["lock_before_suspend"]
    assert "XDG_SESSION_ID" in m["mangoSessionVariables"]
    bar = m["mangobar"]
    assert bar["height"] == 30 and bar["layer"] == "top"
    assert "buffer-scale" not in bar and "keyboardlayout" not in bar
    assert bar["modules-left"] == ["layout", "workspaces"]
    assert bar["modules-center"] == ["window"]
    assert bar["modules-right"] == ["tray", "network", "custom/bluetooth", "battery", "clock"]
    assert bar["window"]["max-length"] == 300 and "on-click" not in bar["window"]
    assert bar["clock"]["format"] == "{:L%m月%d日 周%a %H:%M}"
    assert bar["network"]["format-wifi"] == "{signal}"
    assert ord(bar["network"]["icon-wifi"]) == 0xF05A9
    assert bar["battery"]["on-click"] == "legion-conservation toggle"
    assert bar["battery"]["hide-on-ac"] is False
    assert bar["custom/bluetooth"]["interval"] == 5
    bluetooth_script = Path(m["mangobarBluetoothScript"]).read_text()
    assert "mangobar-bluetooth" in bar["custom/bluetooth"]["exec"]
    # bluetoothctl aborts with SIGABRT and a coredump when the system bus is
    # unreachable; the poll must use busctl and degrade to the off glyph.
    assert "/bin/bluetoothctl" not in bluetooth_script
    assert "bluetoothctl --timeout" not in bluetooth_script
    assert "busctl" in bluetooth_script and "org.bluez" in bluetooth_script
    assert "GetManagedObjects" in bluetooth_script
    assert '"Powered" b true' in bluetooth_script
    assert '"Connected" b true' in bluetooth_script
    assert "U000F00B2" in bluetooth_script
    assert "U000F00B1" in bluetooth_script
    assert "U000F00AF" in bluetooth_script
    assert "timeout 2" in bluetooth_script
    style = m["mangobarStyle"]
    assert 'font-family: "Maple Mono NF CN"' in style
    assert "font-weight: Medium" in style
    assert "text-decoration" not in style and "underline" not in style
    assert "background: none" in style and "border-radius: 0" in style
    assert "#tags.active" in style
    assert m["palette"]["blue"] in style
    # Tray DBusMenu popup: One Dark surface/border/radius, item text, hover
    # highlight and the patched disabled-item colour.
    assert "menu {" in style
    assert "border-radius: 12px" in style
    assert "menuitem:disabled" in style
    for key in ("surface", "border", "selection", "brightFg", "muted"):
        assert m["palette"][key] in style, key
    mangobar_patches = {patch["name"]: patch["content"] for patch in m["mangobarPatches"]}
    assert set(mangobar_patches) == {"menuitem-disabled.patch"}
    disabled_patch = mangobar_patches["menuitem-disabled.patch"]
    assert "menuitem_disabled" in disabled_patch
    assert "lr = dis_r;" in disabled_patch
    # Fully transparent bar: no palette background fill (and no blur opt-in).
    assert (m["palette"]["bg"] + "9e") not in style
    assert "background: none" in style
    assert "margin: 0;" in style
    fuzzel = m["fuzzel"]
    assert fuzzel["main"]["font"] == m["palette"]["fonts"]["sans"] + ":size=14"
    assert fuzzel["main"]["icon-theme"] == m["palette"]["iconTheme"]
    assert fuzzel["main"]["width"] == 60 and fuzzel["main"]["anchor"] == "center"
    assert fuzzel["main"]["lines"] == 8
    assert fuzzel["main"]["horizontal-pad"] == 20 and fuzzel["main"]["vertical-pad"] == 10
    assert fuzzel["main"]["line-height"] == 22
    assert fuzzel["colors"]["background"] == m["palette"]["surface"].removeprefix("#") + "ff"
    assert fuzzel["border"]["width"] == 1
    mako = m["mako"]
    assert not (
        Path(m["makoPackage"]) / "share/dbus-1/services/fr.emersion.mako.service"
    ).exists()
    mako_dbus = m["makoDbusService"]
    assert "Name=org.freedesktop.Notifications" in mako_dbus
    assert "SystemdService=mako.service" in mako_dbus
    assert mako["anchor"] == "top-right" and mako["width"] == 360
    assert mako["background-color"] == m["palette"]["surface"]
    assert mako["outer-margin"] == "42,28,0,0" and mako["margin"] == "0,0,8,0"
    assert mako["max-visible"] == 3 and mako["border-size"] == 1
    on_notify = mako["on-notify"]
    assert on_notify.startswith("exec ")
    assert "/bin/pw-play" in on_notify
    assert "message-new-instant.oga" in on_notify
    logical = 1600 / 1.5
    assert abs(m["swayosd"]["topMargin"] - ((logical - 96 - 26) / logical)) < 1e-6
    swayosd_style = Path(m["swayosd"]["style"]).read_text()
    assert "border-radius: 999px" in swayosd_style
    assert m["palette"]["surface"] in swayosd_style
    assert "show_percentage = true" in m["swayosdConfig"]
    # Lock-key OSD comes from the root libinput backend, not key bindings.
    backend = m["swayosdBackend"]
    assert backend["wantedBy"] == [ "multi-user.target" ]
    assert backend["execStart"].endswith("/bin/swayosd-libinput-backend")
    assert backend["restart"] == "always"
    assert m["swayosdSystemBusPolicy"]
    assert "org.erikreider.swayosd-libinput-backend" in m["swayosdPolkit"]
    assert "margin: 8px 14px" in swayosd_style
    assert "font-size: 13px" in swayosd_style
    assert "min-height: 4px" in swayosd_style
    # swayosd 0.3.1's config parser rejects unknown keys and panics, so the
    # config must not carry keys its schema does not know.
    assert "duration" not in m["swayosdConfig"]
    assert m["videoGroup"] and m["swayosdUdev"]
    assert widgets["lockscreen-login-box@eDP-1"]["settings"]["background_opacity"] == 0.0
    assert m["palette"]["fonts"]["sans"] in m["greeter"]["css"]
    assert "noctalia-firefox" in settings["theme"]["templates"]["user"]
    assert "noctalia-mango" not in settings["theme"]["templates"]["user"]
    assert settings["shell"]["launch_apps_as_systemd_services"]
    for name, unit in m["units"].items():
        targets = m["sharedTargets"] if name in ("fcitx5-daemon", "xrdb-merge") else ["mango-session.target"]
        assert unit["Unit"]["PartOf"] == targets, name
        assert unit["Unit"]["After"] == targets, name
        assert unit["Install"]["WantedBy"] == targets, name
    for name in ("mangobar", "mako", "swayosd", "cliphist", "cliphist-images", "wl-clip-persist"):
        assert name in m["units"], name
    mangobar_unit = m["units"]["mangobar"]
    assert mangobar_unit["Service"]["Restart"] == "on-failure"
    assert mangobar_unit["Service"]["RestartSec"] in (2, "2")
    assert mangobar_unit["Unit"]["StartLimitBurst"] == 3
    assert "LC_TIME=zh_CN.UTF-8" in mangobar_unit["Service"]["Environment"]
    mako_unit = m["units"]["mako"]
    assert mako_unit["Service"]["Type"] == "dbus"
    assert mako_unit["Service"]["BusName"] == "org.freedesktop.Notifications"
    assert mako_unit["Service"]["Restart"] == "always"
    def command(value):
        return "\n".join(value) if isinstance(value, list) else str(value)
    swayosd_exec = command(m["units"]["swayosd"]["Service"]["ExecStart"])
    assert "swayosd-libinput" not in swayosd_exec
    assert "--top-margin" in swayosd_exec
    assert m["units"]["swayosd"]["Unit"]["StartLimitBurst"] == 3
    assert m["units"]["cliphist"]["Service"]["Restart"] == "always"
    assert m["units"]["cliphist-images"]["Service"]["Restart"] == "always"
    assert "--reconnect-tries 0" in command(m["units"]["wl-clip-persist"]["Service"]["ExecStart"])
    assert m["units"]["wl-clip-persist"]["Service"]["Restart"] == "always"
    noctalia = m["units"]["noctalia"]
    assert noctalia["Service"]["Restart"] == "on-failure"
    assert noctalia["Unit"]["StartLimitBurst"] == 3
    assert noctalia["Service"]["ExecStartPre"]
    assert noctalia["Service"]["UnsetEnvironment"] == ["LC_ALL"]
    env = dict(value.split("=", 1) for value in noctalia["Service"]["Environment"])
    assert env["QT_QPA_PLATFORMTHEME"] == "qt6ct" and env["XMODIFIERS"] == "@im=fcitx"
    assert not any("KEY" in key or "TOKEN" in key or "SECRET" in key for key in env)
    assert "NVIM_CLAUDE_ACP" not in env
    assert "NVIM_CLAUDE_ACP" not in m["environment"]
    assert "NVIM_CLAUDE_ACP" not in m["shellEnvironment"]
    assert m["palette"]["bg"] in m["greeter"]["css"]
    assert "output eDP-1 scale 1.5" in m["greeter"]["sway"]
    session = m["greeter"]["environments"].strip()
    assert " " not in session and len(session) < 128
    assert session in m["greeter"]["sway"]
    login = Path(session).read_text()
    assert "XDG_SESSION_TYPE=wayland" in login
    assert "XDG_CURRENT_DESKTOP=mango:wlroots" in login
    assert "XDG_SESSION_DESKTOP=mango" in login
    PY
  ''
