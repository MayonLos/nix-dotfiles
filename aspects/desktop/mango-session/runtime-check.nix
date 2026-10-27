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
  # Use the host's generated fontconfig rules with an isolated home. This checks
  # family selection and missing-glyph fallback without applying the system.
  fontConfig = pkgs.makeFontsConf {
    fontDirectories = host.fonts.packages;
    impureFontDirectories = [ ];
    includes = [ "${host.environment.etc.fonts.source}/conf.d" ];
  };
  overlayClearanceCheck =
    pkgs.runCommand "noctalia-overlay-clearance"
      {
        nativeBuildInputs = [
          pkgs.patch
          pkgs.stdenv.cc
        ];
      }
      ''
        cp -R ${home.programs.noctalia.package.src} source
        chmod -R u+w source
        cd source
        ${pkgs.lib.concatMapStringsSep "\n" (
          patch: "patch -p1 --fuzz=0 < ${patch}"
        ) home.programs.noctalia.package.patches}
        c++ -std=c++20 -I src ${./resources/overlay-clearance-test.cpp} -o overlay-clearance-test
        ./overlay-clearance-test
        touch "$out"
      '';
  metadata = pkgs.writeText "desktop-contract.json" (
    builtins.toJSON {
      overlayClearanceCheck = toString overlayClearanceCheck;
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
      units = pkgs.lib.getAttrs [
        "noctalia"
        "fcitx5-daemon"
        "clipboard-bridge"
        "xrdb-merge"
      ] home.systemd.user.services;
      environment = home.systemd.user.sessionVariables;
      shellEnvironment = home.home.sessionVariables;
      fcitxClassicUI = home.i18n.inputMethod.fcitx5.settings.addons.classicui.globalSection;
      acpEnvironment = {
        NVIM_CODEX_ACP = "${pkgs.local.codex-acp}/bin/codex-acp";
        NVIM_CLAUDE_ACP = "${pkgs.local.claude-agent-acp}/bin/claude-agent-acp";
      };
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
        ansi = import ../../appearance/appearance/ansi.nix palette;
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
    ${pkgs.lib.getExe home.programs.noctalia.package} plugins lint ${./resources/noctalia-plugins} > "$out/plugins.log" 2>&1 || { cat "$out/plugins.log"; exit 1; }
    lua ${./resources/test-conservation.lua} ${./resources/noctalia-plugins/legion-conservation/status.luau} > "$out/conservation.log"
    ${pkgs.lib.getExe home.wayland.windowManager.mango.package} -c ${
      home.xdg.configFile."mango/config.conf".source
    } -p > "$out/mango.log" 2>&1 || { cat "$out/mango.log"; exit 1; }
    if grep -iE 'conflict|unknown|invalid|error' "$out/mango.log"; then exit 1; fi
    # Retain the actual generated inputs beside the pinned parser logs.
    cp ${home.xdg.configFile."mango/config.conf".source} "$out/mango.conf"
    cp ${home.xdg.configFile."noctalia/config.toml".source} "$out/noctalia.toml"
    python3 ${./resources/window-rules-check.py} "$out/mango.conf"
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
    for name, marker in {"hud-overlay-clearance.patch": "HUD33: output-local logical coordinates", "hud-bar.patch": "HUD27: native faded separator", "hud-tooltips.patch": "TooltipPanel", "hud-sysmon.patch": "hide_unavailable", "hud-controls-tooltips.patch": "TooltipPanel", "hud-battery.patch": "label_outside", "hud-balanced.patch": "temperature_hide_below", "hud-drawer-clearance.patch": "kHudCenterClearance = 24.0F"}.items():
        assert name in patches and marker in patches[name], (name, patches.keys())
    # Check serialized settings too: validating the Nix attrset alone would
    # miss a lost/renamed field during Home Manager's config generation.
    generated = tomllib.loads(Path(sys.argv[4]).read_text())
    expected = {
        ("shell", "launcher", "layout"): "full",
        ("shell", "launcher", "width"): 520,
        ("shell", "launcher", "category_icons_only"): True,
        ("shell", "app_icon_colorize"): False,
        ("control_center", "sidebar"): "none",
        ("control_center", "width"): 380,
        ("notification", "width"): 320,
        ("bar", "main", "thickness"): 35,
        ("bar", "main", "radius"): 9,
        ("bar", "main", "margin_ends"): 8,
        ("bar", "main", "margin_edge"): 6,
        ("bar", "main", "font_scale"): 0.93,
        ("bar", "main", "widget_spacing"): 6,
        ("bar", "main", "padding"): 7,
        ("bar", "main", "capsule_radius"): 6,
        ("bar", "main", "capsule"): False,
        ("widget", "control-center", "glyph"): "settings",
        ("widget", "clock-date", "format"): "{:%m月%d日 周%a}",
        ("widget", "clock-time", "format"): "{:%H:%M}",
        ("widget", "clock-time", "font_weight"): 600,
        ("widget", "workspaces", "style"): "minimal",
        ("widget", "battery", "label_content"): "percent",
        ("widget", "battery", "display_mode"): "graphic",
        ("widget", "battery", "label_outside"): True,
        ("widget", "tray", "drawer"): True,
        ("widget", "tray", "pinned"): ["fcitx"],
        ("widget", "battery", "actions", "left"): "exec legion-conservation toggle",
        ("widget", "monitor-cpu", "visualization"): "graph",
        ("widget", "monitor-memory", "visualization"): "ring",
        ("widget", "monitor-gpu", "visualization"): "ring",
        ("widget", "control-center", "icon_color"): m["palette"]["fg"],
        ("widget", "fel/quill:status", "icon_color"): m["palette"]["muted"],
        ("widget", "battery", "graphic_color"): m["palette"]["fg"],
        ("widget", "battery", "charging_color"): m["palette"]["green"],
        ("widget", "battery", "critical_color"): m["palette"]["red"],
        ("widget", "battery", "critical_threshold"): 10,
        ("widget", "workspaces", "empty_color"): m["palette"]["border"] + "99",
        ("widget", "monitor-temp", "stat"): "cpu_temp",
        ("widget", "monitor-gpu", "hide_unavailable"): True,
        ("widget", "monitor-gpu", "show_gpu_temperature"): False,
        ("widget", "monitor-temp", "temperature_hide_below"): 80,
        ("widget", "monitor-temp", "hide_unavailable"): True,
        ("widget", "volume", "show_label"): False,
        ("bar", "main", "capsule_thickness"): 0.67,
        ("widget", "workspaces", "hide_when_empty"): True,
        ("widget", "workspaces", "minimum_visible"): 5,
        ("system", "monitor", "gpu_poll_seconds"): 2.0,
        ("system", "monitor", "gpu_only_nvidia"): True,
        ("widget", "separator-monitor", "length"): 15,
        ("widget", "separator-control", "length"): 15,
        ("widget", "clock-dot", "length"): 24,
        ("widget", "clock-dot", "decoration"): "dot",
        ("widget", "monitor-gpu", "stat"): "gpu_usage",
        ("widget", "monitor-memory", "stat"): "ram_pct",
        ("shell", "launcher", "default_view"): "pinned",
        ("shell", "launcher", "track_usage"): True,
        ("shell", "launcher", "sort_by_usage"): True,
        ("shell", "launcher", "pinned"): ["kitty", "nvim", "firefox", "thunar"],
        ("shell", "launcher", "providers", "calculator", "global"): False,
        ("notification", "border_color"): "outline_variant",
        ("notification", "border_width"): 1,
        ("osd", "border_color"): "outline_variant",
        ("osd", "border_width"): 1,
        ("shell", "show_close_buttons"): False,
        ("theme", "sync_color_scheme"): False,
        ("shell", "panel", "border_color"): "outline_variant",
        ("shell", "panel", "border_width"): 1,
        ("bar", "main", "show_tooltip"): True,
        ("lockscreen_widgets", "widget", "lockscreen-login-box@eDP-1", "settings", "show_password_reveal"): True,
        ("lockscreen_widgets", "widget", "lockscreen-login-box@eDP-1", "settings", "input_radius"): 8.0,
    }
    for keys, value in expected.items():
        for root in (settings, generated):
            for key in keys:
                root = root[key]
            assert root == value, (keys, root, value)
    groups = {group["id"]: group for group in settings["bar"]["main"]["capsule_group"]}
    assert all(group["opacity"] == 0 for group in groups.values())
    assert groups["tools"]["members"] == ["fel/quill:status", "8bury/mini-docker:mini-docker", "rxtsel/portctl:indicator", "brightness", "power_profile", "caffeine"]
    assert groups["tools"]["accordion"] and groups["tools"]["border_width"] == 0
    assert {name: group["padding"] for name, group in groups.items()} == {
        "time": 4.0,
        "tools": 4.0,
        "monitor": 2.0,
        "system": 4.0,
    }
    assert {name: group["widget_spacing"] for name, group in groups.items()} == {
        "time": 7,
        "tools": 10,
        "monitor": 6,
        "system": 8,
    }
    assert not groups["monitor"]["accordion"]
    assert groups["monitor"]["members"] == ["monitor-cpu", "monitor-memory", "monitor-gpu", "monitor-temp"]
    for root in (settings, generated):
        bar = root["bar"]["main"]
        assert bar["start"] == ["launcher", "separator-workspaces", "workspaces", "separator-layout", "gambled23/mangowm-keymode:mangowm-keymode", "ezequiel/mango_layouts:btn", "group:tools"]
        assert bar["center"] == ["group:time"]
        assert bar["end"] == ["group:monitor", "separator-monitor", "group:system", "separator-control", "control-center"]
        actual_groups = {group["id"]: group for group in bar["capsule_group"]}
        assert actual_groups["system"]["members"] == ["network", "bluetooth", "volume", "tray", "battery", "notifications"]
        assert actual_groups["system"]["widget_spacing"] == 8
        assert actual_groups["monitor"]["widget_spacing"] == 6
        assert actual_groups["monitor"]["padding"] == 2.0
        assert actual_groups["monitor"]["members"] == ["monitor-cpu", "monitor-memory", "monitor-gpu", "monitor-temp"]
        assert actual_groups["monitor"]["opacity"] == 0 and actual_groups["monitor"]["border_width"] == 0
        assert not root["widget"]["monitor-gpu"]["capsule"] and root["widget"]["monitor-gpu"]["hide_unavailable"]
        assert all(not root["widget"][name]["capsule"] for name in ("monitor-gpu", "ezequiel/mango_layouts:btn"))
        assert bar["border_width"] == 1 and bar["border"] == m["palette"]["muted"] + "55"
        assert "monitor-vram" not in root["widget"]
        for name, accent in (("monitor-cpu", "blue"), ("monitor-memory", "green"), ("monitor-gpu", "cyan")):
            widget = root["widget"][name]
            assert widget["color"] == m["palette"]["brightFg"]
            assert widget["label_color"] == m["palette"]["muted"]
            assert widget["highlight_color"] == m["palette"][accent]
            assert widget["warning_threshold"] == 70 and widget["critical_threshold"] == 90
            assert widget["warning_color"] == m["palette"]["yellow"]
            assert widget["critical_color"] == m["palette"]["red"]
            assert widget["font_family"] == m["palette"]["fonts"]["mono"]
        assert root["battery"]["warning_threshold"] == 20
        assert root["widget"]["monitor-temp"]["color"] == m["palette"]["orange"]
        assert "glyph" not in root["widget"]["fel/quill:status"]
        assert root["widget"]["monitor-temp"]["custom_label"] == ""
        assert all(root["widget"][name]["label_min_width"] == 22 for name in ("monitor-cpu", "monitor-memory", "monitor-gpu"))
        assert root["widget"]["monitor-temp"]["label_min_width"] == 26
        assert all(
            settings.get("scale") == 1.15
            for settings in root["widget"].values()
            if settings.get("type") != "spacer"
        )
        bar_widgets = bar["start"] + bar["center"] + bar["end"]
        bar_widgets = [name for name in bar_widgets if not name.startswith("group:")]
        bar_widgets += [member for group in bar["capsule_group"] for member in group["members"]]
        assert all(
            root["widget"].get(name, {}).get("scale") == 1.15
            for name in set(bar_widgets)
            if root["widget"].get(name, {}).get("type") != "spacer"
        )
    assert "R31: flat One Dark surface" in patches["hud-bar.patch"]
    assert "hudLineStyle" not in patches["hud-bar.patch"]
    for marker in ("R35: smaller unread dot with a bar-surface outline", "kDotBaseSize = 5.0F", ".border = colorSpecFromRole(ColorRole::Surface)", ".borderWidth = 1.0F * m_contentScale", "itemW - 4.0F)) : 2.0F", ": colorSpecFromRole(ColorRole::OutlineVariant)"):
        assert marker in patches["hud-bar.patch"], marker
    for marker in ("warning_threshold", "critical_threshold", "warning_color", "critical_color", "label_color", "graph->setFillOpacity(0.18F)", "baseSize * 0.17F", "m_graph->setColor(currentValueColor(m_highlightColor))", "m_ringFill->setColor(currentValueColor(m_highlightColor))"):
        assert marker in patches["hud-sysmon.patch"], marker
    for marker in ("usage >= m_criticalThreshold", "usage >= m_warningThreshold", "Style::rtl() ? TextAlign::Start : TextAlign::End"):
        assert marker in patches["hud-balanced.patch"], marker
    for marker in ("R35: low/critical charge wins over charging", "scaleAlpha(graphic, 0.85F)", "R35: charging bolt is inset in the battery", "R35: alert-colored bolt remains visible", "graphic_color", "charging_color", "critical_threshold"):
        assert marker in patches["hud-battery.patch"], marker
    assert "0x98C379" not in patches["hud-battery.patch"]
    assert "R31: minimal reuses the indicator" in patches["hud-bar.patch"]
    assert "contentMainEnd - centerSlotEnd - (isVertical ? 0.0F : kHudCenterClearance)" in patches["hud-drawer-clearance.patch"]
    clearance = patches["hud-drawer-clearance.patch"]
    for marker in ('centerSlotStart - contentMainStart - (isVertical ? 0.0F : kHudCenterClearance)', 'instance.endSection->width() > endSlotMain', 'setDrawerCompact(false)', 'setDrawerCompact(true)', 'm_compactDot->setVisible(m_drawerCompact)', 'panel.summary = available ? profile', '+  rootNode->setSize(m_glyph->width(), m_glyph->height());'):
        assert marker in clearance, marker
    assert '+  m_label->setText' not in clearance
    balanced = patches["hud-balanced.patch"]
    for marker in ('currentGradientValue() >= 90.0', 'currentStats.cpuTempC.value_or(0.0) >= m_temperatureHideBelow', 'rootNode->setParticipatesInLayout(shown)', 'addMetric(SysmonStat::GpuVram, "VRAM"', 'addMetric(SysmonStat::GpuTemp, "独显温度"', 'm_monitor->retainGpuVram()', 'm_monitor->releaseGpuVram()'):
        assert marker in balanced, marker
    assert not any(w.get("text") == "│" for w in settings["widget"].values())
    assert all(settings["widget"][name]["type"] == "spacer" for name in settings["widget"] if name.startswith("separator-"))
    assert len(settings["control_center"]["shortcuts"]) == 6
    enabled_plugins = settings["plugins"]["enabled"]
    assert "tmelik/system-monitor" not in enabled_plugins
    assert "mindnbytes/nix-status" not in enabled_plugins
    assert "knyrps/nix-search" in enabled_plugins
    assert "nix-dotfiles/legion-conservation" in enabled_plugins
    for root in (settings, generated):
        assert "mindnbytes/nix-status" not in root["plugin_settings"]
        assert "mindnbytes/nix-status:status" not in root["widget"]
    assert p["dark"]["mOutline"] == m["palette"]["border"]
    assert abs(settings["shell"]["corner_radius_scale"] - 4 / 3) < 1e-6
    assert settings["shell"]["corner_radius_scale"] == m["greeter"]["appearance"]["corner_radius_scale"]
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
    assert mango["blur"] == mango["blur_layer"] == mango["layer_shadows"] == mango["layer_animations"] == 0
    assert settings["shell"]["panel"]["shadow"] and settings["bar"]["main"]["shadow"]
    assert mango["border_px"] == 2 and mango["border_radius"] == 10
    assert mango["focus_color"] == "0x" + m["palette"]["blue"].removeprefix("#") + "ff"
    assert mango["gap_inner_horizontal"] == mango["gap_inner_vertical"] == 8
    assert mango["gap_outer_horizontal"] == mango["gap_outer_vertical"] == 12
    assert mango["overview_gap_inner"] == 16 and mango["overview_gap_outer"] == 32
    assert mango["shadows_position_x"] == 0 and mango["shadows_position_y"] == 6
    assert mango["shadows_color"] == "0x" + m["palette"]["black"].removeprefix("#") + "52"
    assert mango["shadow_only_floating"] == 1 and "focused_shadows_color" not in mango
    assert mango["dim_enable"] == 1
    assert mango["dim_focused_color"] == "0x" + m["palette"]["black"].removeprefix("#") + "00"
    assert mango["dim_unfocused_color"] == "0x" + m["palette"]["black"].removeprefix("#") + "10"
    assert mango["focus_on_activate"] == 0
    assert mango["allow_tearing"] == 2
    assert mango["animations"] == (0 if m["palette"]["reducedMotion"] else 1)
    for event in ("open", "close", "move", "tag"):
        assert 150 <= mango["animation_duration_" + event] <= 200
        assert mango["animation_curve_" + event] == "0.16,1.0,0.3,1.0"
    assert m["fcitxClassicUI"]["PreferTextIcon"] == "True"
    assert "keyboard_layout" not in [member for group in settings["bar"]["main"]["capsule_group"] for member in group["members"]]
    assert m["environment"]["XCURSOR_THEME"] == m["palette"]["cursor"]["name"]
    assert m["environment"]["XCURSOR_SIZE"] == str(m["palette"]["cursor"]["size"])
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
    assert wallpaper["automation"] == {"enabled": True, "order": "random", "interval_seconds": 86400, "recursive": True}
    managed_source = Path(m["wallpaperManagedSource"])
    expected_names = sorted(f"wallpaper-{suffix}.png" for suffix in ("002", "005", "008", "009", "011"))
    assert sorted(asset["name"] for asset in m["wallpaperAssets"]) == expected_names
    assert sorted(path.name for path in managed_source.iterdir()) == expected_names
    assert all(path.is_symlink() and path.is_file() for path in managed_source.iterdir())
    assert Path(wallpaper["default"]["path"]).resolve() == Path(m["wallpaperFactoryDefault"]).resolve()
    assert Path(m["greeter"]["appearance"]["wallpaper"]["path"]).resolve() == Path(m["wallpaperFactoryDefault"]).resolve()
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
    seconds = widgets["lockscreen-widget-seconds"]["settings"]
    assert seconds["format"] == "{:%S}" and seconds["color"] == "outline_variant"
    for name in ("clock", "date", "seconds"):
        assert widgets["lockscreen-widget-" + name]["settings"]["font_family"] == m["palette"]["fonts"]["mono"]
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
    mango_env = dict(value.split(",", 1) for value in mango["env"])
    for name, path in m["acpEnvironment"].items():
        assert m["shellEnvironment"][name] == m["environment"][name] == env[name] == mango_env[name] == path
        assert path.startswith("/nix/store/") and os.access(path, os.X_OK), (name, path)
    assert not any("KEY" in key or "TOKEN" in key or "SECRET" in key for key in env)
    assert m["greeter"]["appearance"]["palette"]["surface"] == m["palette"]["bg"]
    assert m["greeter"]["output"]["scales"] == "eDP-1:1.5"
    PY
  ''
