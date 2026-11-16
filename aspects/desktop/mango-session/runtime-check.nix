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
  python = pkgs.python3;
  # Use the host's generated fontconfig rules with an isolated home. This checks
  # family selection and missing-glyph fallback without applying the system.
  fontConfig = pkgs.makeFontsConf {
    fontDirectories = host.fonts.packages;
    impureFontDirectories = [ ];
    includes = [ "${host.environment.etc.fonts.source}/conf.d" ];
  };
  # Session environment is a filtered whitelist, not the whole HM environment.
  # Keep the projection in the metadata so the checker can compare it with the
  # values Mango receives in its generated config.
  allowedSessionVariables =
    (import ./session-environment.nix { inherit (pkgs) lib; })
      home.systemd.user.sessionVariables;
  metadata = pkgs.writeText "desktop-contract.json" (
    builtins.toJSON {
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
        "fcitx5-daemon"
        "clipboard-bridge"
        "xrdb-merge"
        "mangobar"
        "mako"
        "swayosd"
        "sweetbgd"
        "swayidle"
        "polkit-gnome-authentication-agent-1"
        "cliphist"
        "cliphist-images"
        "wl-clip-persist"
      ] home.systemd.user.services;
      mangobar = home.services.mangobar.settings;
      mangobarStyle = home.xdg.configFile."mangobar/style.css".text;
      clipboardHistory =
        let
          match = builtins.filter (
            pkg: (builtins.parseDrvName pkg.name).name == "clipboard-history"
          ) home.home.packages;
        in
        if match == [ ] then
          throw "clipboard-history is not installed in the session"
        else
          "${builtins.head match}/bin/clipboard-history";
      mangobarPatches = map (path: {
        name = builtins.baseNameOf path;
        content = builtins.readFile path;
      }) home.services.mangobar.package.patches;
      fuzzel = home.programs.fuzzel.settings;
      cliphistTuiNix = builtins.readFile ./cliphist-tui.nix;
      cliphistTuiPatch = builtins.readFile ./resources/cliphist-tui-keep-history.patch;
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
      sweetbgConfig = home.xdg.configFile."sweetbg/config.toml".text;
      wallpaperApply =
        let
          match = builtins.filter (
            pkg: (builtins.parseDrvName pkg.name).name == "wallpaper-apply"
          ) home.home.packages;
        in
        if match == [ ] then
          throw "wallpaper-apply is not installed in the session"
        else
          "${builtins.head match}/bin/wallpaper-apply";
      wallpaperPick =
        let
          match = builtins.filter (
            pkg: (builtins.parseDrvName pkg.name).name == "wallpaper-pick"
          ) home.home.packages;
        in
        if match == [ ] then
          throw "wallpaper-pick is not installed in the session"
        else
          "${builtins.head match}/bin/wallpaper-pick";
      swaylock = {
        enable = home.programs.swaylock.enable;
        settings = home.programs.swaylock.settings;
        pamService = host.security.pam.services ? swaylock;
      };
      swayidle = {
        enable = home.services.swayidle.enable;
        timeouts = home.services.swayidle.timeouts;
        events = home.services.swayidle.events;
      };
      environment = home.systemd.user.sessionVariables;
      shellEnvironment = home.home.sessionVariables;
      inherit allowedSessionVariables;
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
    ];
  }
  ''
    export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/config" XDG_CACHE_HOME="$TMPDIR/cache" XDG_STATE_HOME="$TMPDIR/state" XDG_DATA_HOME="$TMPDIR/data"
    mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" "$XDG_DATA_HOME" "$out"
    ${pkgs.lib.getExe home.wayland.windowManager.mango.package} -c ${
      home.xdg.configFile."mango/config.conf".source
    } -p > "$out/mango.log" 2>&1 || { cat "$out/mango.log"; exit 1; }
    if grep -iE 'conflict|unknown|invalid|error' "$out/mango.log"; then exit 1; fi
    # Retain the actual generated input beside the pinned parser log.
    cp ${home.xdg.configFile."mango/config.conf".source} "$out/mango.conf"
    python3 ${./resources/window-rules-check.py} "$out/mango.conf"
    python3 ${./mango/check-window-rules.py} "$out/mango.conf" > "$out/window-rules.log"
    export FONTCONFIG_FILE=${fontConfig}
    fc-match -f '%{family}\n' sans-serif | tee "$out/sans-family.txt"
    grep -Fx '${palette.fonts.sans}' "$out/sans-family.txt"
    fc-match -f '%{family}\n' monospace | tee "$out/mono-family.txt"
    grep -Fx '${palette.fonts.mono}' "$out/mono-family.txt"
    fc-match -f '%{family}\n' '${palette.fonts.sans}:lang=zh-cn:charset=4e2d' | tee "$out/cjk-fallback.txt"
    grep -Fx '${palette.fonts.cjk}' "$out/cjk-fallback.txt"
    python3 - ${avatarMetadata} <<'PY'
    import json, sys
    from pathlib import Path
    data = json.load(open(sys.argv[1]))
    assert data["homeSource"] == data["hostSource"], data
    assert Path(data["homeSource"]).is_file()
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

    python3 - ${metadata} "$out/mango.conf" "$out" <<'PY'
    import json, os, re, shutil, subprocess, sys
    from pathlib import Path
    m = json.load(open(sys.argv[1]))
    conf = Path(sys.argv[2]).read_text()
    out = Path(sys.argv[3])
    palette = m["palette"]

    # Mango: keep the generated layout and palette contract observable.
    mango = m["mango"]
    assert mango["blur"] == mango["blur_layer"] == 1
    assert mango["layer_shadows"] == mango["layer_animations"] == 0
    assert mango["blur_optimized"] == 1
    assert mango["layer_rule"] == [
        "layer_name:.*,no_blur:1",
        "layer_name:^mangobar$,no_blur:1,no_animation:1,no_shadow:1",
        "layer_name:^notifications$,no_animation:1,no_blur:1,no_shadow:1",
        "layer_name:^swayosd$,no_animation:1,no_blur:1,no_shadow:1",
    ]
    assert mango["window_rule"][0] == "force_tearing:0,no_blur:1,app_id:.*"
    assert mango["zoom_initial_ratio"] == 0.92 and mango["zoom_end_ratio"] == 0.92
    assert mango["fade_in_begin_opacity"] == 0 and mango["fade_out_begin_opacity"] == 1
    assert mango["animation_type_open"] == mango["animation_type_close"] == "zoom"
    assert mango["animations"] == (0 if palette["reducedMotion"] else 1)
    for event, duration in {"open": 220, "close": 180, "move": 180, "tag": 280, "focus": 120}.items():
        assert mango["animation_duration_" + event] == duration
        assert mango["animation_curve_" + event] == "0.16,1.0,0.3,1.0"
    assert mango["cursor_theme"] == palette["cursor"]["name"]
    assert mango["cursor_size"] == palette["cursor"]["size"]
    assert mango["border_px"] == 2 and mango["border_radius"] == 16
    assert mango["border_color"] == "0x" + palette["border"].removeprefix("#") + "ff"
    assert mango["focus_color"] == "0x" + palette["blue"].removeprefix("#") + "ff"
    assert mango["gap_inner_horizontal"] == mango["gap_inner_vertical"] == 10
    assert mango["gap_outer_horizontal"] == mango["gap_outer_vertical"] == 16
    assert mango["smart_gaps"] == mango["no_border_when_single"] == mango["no_radius_when_single"] == 0
    assert mango["monocle_no_border"] == mango["monocle_no_gap"] == mango["monocle_no_radius"] == 1
    assert mango["overview_gap_inner"] == 12 and mango["overview_gap_outer"] == 24
    assert mango["overcircle_center_ratio"] == 0.68
    assert mango["shadows_position_x"] == 0 and mango["shadows_position_y"] == 10
    assert mango["shadows_size"] == 18 and mango["shadows_blur"] == 32
    assert mango["shadows_color"] == "0x" + palette["black"].removeprefix("#") + "66"
    assert mango["shadow_only_floating"] == 1 and "focused_shadows_color" not in mango
    assert mango["dim_enable"] == 1
    assert mango["dim_focused_color"] == "0x" + palette["black"].removeprefix("#") + "00"
    assert mango["dim_unfocused_color"] == "0x" + palette["black"].removeprefix("#") + "18"
    assert mango["focus_on_activate"] == 0
    assert mango["allow_tearing"] == 2
    assert mango["root_color"] == "0x" + palette["bg"].removeprefix("#") + "ff"
    assert mango["drop_color"] == "0x" + palette["blue"].removeprefix("#") + "80"
    assert mango["split_color"] == "0x" + palette["cyan"].removeprefix("#") + "ff"
    assert "XDG_SESSION_ID" in m["mangoSessionVariables"]
    # Every env row is from the whitelisted static projection and matches it.
    allowed = m["allowedSessionVariables"]
    assert isinstance(allowed, dict) and allowed
    for row in mango["env"]:
        name, value = row.split(",", 1)
        assert allowed.get(name) == value, (name, value, allowed.get(name))
    assert not any("/" in name for name in allowed)

    # Bindings: the standalone session keeps fuzzel, clipboard history,
    # swaylock, swayosd and OCR; the old shell controls are gone.
    bind = mango["bind"]
    assert "ALT,space,spawn,fuzzel --no-icons" in bind
    assert "SUPER,V,spawn,clipboard-history" in bind
    assert not any(item.startswith("SUPER,A,") for item in bind)
    assert "SUPER+ALT,L,spawn,session-lock" in bind
    assert "SUPER,Print,spawn,ocr-region" in bind
    assert "SUPER+SHIFT,Print,spawn,ocr-screen" in bind
    assert "SUPER+SHIFT,T,switcher,next" in bind
    assert "SUPER,Equal,switch_layout" in bind
    assert "SUPER,Minus,setmfact,-0.05" in bind
    assert "SUPER+CTRL,Equal,setmfact,+0.05" in bind
    assert "SUPER+SHIFT,Equal,resizewin,+0,+10" in bind
    assert "SUPER,W,spawn,wallpaper-pick" in bind
    assert "SUPER+ALT,J,overcircle,current_prev" in bind
    assert "SUPER+ALT,K,overcircle,current_next" in bind
    assert "SUPER,0,toggleoverview" in bind
    assert not any(item.startswith("SUPER+SHIFT,W,") for item in bind)
    assert mango["circle_layout"] == "tile,scroller,monocle"
    assert mango["tag_rule"] == [ "id:*,layout_name:tile" ]
    assert mango["default_master_factor"] == 0.6
    hardware = mango["key_mode"]["common"]["bindl"]
    assert "NONE,XF86AudioRaiseVolume,spawn,swayosd-client --output-volume raise" in hardware
    assert "NONE,XF86AudioLowerVolume,spawn,swayosd-client --output-volume lower" in hardware
    assert "NONE,XF86AudioMute,spawn,swayosd-client --output-volume mute-toggle" in hardware
    assert "NONE,XF86MonBrightnessUp,spawn,swayosd-client --brightness raise" in hardware
    assert "NONE,XF86MonBrightnessDown,spawn,swayosd-client --brightness lower" in hardware
    assert "NONE,XF86AudioMicMute,spawn,swayosd-client --input-volume mute-toggle" in hardware
    assert "SUPER,R,setkeymode,resize" in bind
    assert "SUPER+SHIFT,T,switcher,next" in bind
    for chord, scratch, tool in (("SUPER+SHIFT,D,", "mayon-tools", "mayon-tools"), ("SUPER+SHIFT,B,", "mayon-bili", "bilitui-mayon")):
        matches = [binding for binding in bind if binding.startswith(chord)]
        assert len(matches) == 1
        assert f"toggle_named_scratchpad,{scratch}," in matches[0] and f"--class={scratch} " in matches[0]
        assert matches[0].split()[-1].endswith(tool)
    voice = [binding for binding in mango["bindr"] if binding.startswith("SUPER+SHIFT,XF86Assistant,")]
    assert len(voice) == 1 and voice[0].endswith("/bin/mayon-voice toggle")

    # Source patches still declare the two Mango changes this fork relies on.
    patches = {patch["name"]: patch["content"] for patch in m["mangoPatches"]}
    center_patch = patches["r52-center-rule-sized-floats.patch"]
    assert "!c->iscustomsize" in center_patch
    assert "c->iscustomsize || !client_is_x11(c)" in center_patch

    parsed = {}
    for line in conf.splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            key, value = line.split("=", 1)
            parsed[key.strip()] = value.strip()
    prefix = "title_message_bar_"
    title = {"height": 48, "gap": 12, "decorate_font_desc": palette["fonts"]["mono"] + " 10.5",
             "decorate_border_width": 1, "decorate_corner_radius": 8,
             "decorate_padding_x": 8, "decorate_padding_y": 4}
    for suffix, role in {"fg_color": "fg", "bg_color": "deep", "focus_fg_color": "blue",
                         "focus_bg_color": "selection", "border_color": "border"}.items():
        title["decorate_" + suffix] = "0x" + palette[role].removeprefix("#") + "ff"
    for suffix, value in title.items():
        key = prefix + suffix
        assert mango[key] == value, (key, mango[key], value)
        assert parsed[key] == str(value), (key, parsed[key], value)
    assert {key for key in parsed if key.startswith(prefix)} == {prefix + key for key in title}
    assert m["fcitxClassicUI"]["PreferTextIcon"] == "True"

    # Wallpaper: one sweetbgd daemon owns the layer surface. Its declarative
    # config starts on the factory image; ExecStartPost restores the saved
    # choice after every daemon start. The picker only calls wallpaper-apply.
    def unit_command(value):
        return "\n".join(value) if isinstance(value, list) else str(value)

    sweetbg = m["units"]["sweetbgd"]
    assert unit_command(sweetbg["Service"]["ExecStart"]).endswith("/bin/sweetbgd")
    assert "--restore" in unit_command(sweetbg["Service"]["ExecStartPost"])
    assert sweetbg["Service"]["Restart"] == "always"
    sweetbg_config = m["sweetbgConfig"]
    assert f'image = "{m["wallpaperFactoryDefault"]}"' in sweetbg_config
    assert f'color = "{palette["bg"]}"' in sweetbg_config
    assert 'fit = "cover"' in sweetbg_config
    wallpaper_apply = Path(m["wallpaperApply"]).read_text()
    assert "sweetbg" in wallpaper_apply and " img " in wallpaper_apply
    assert "--restore" in wallpaper_apply and "query" in wallpaper_apply
    assert ".local/state/mango-session" in wallpaper_apply
    wallpaper_pick = Path(m["wallpaperPick"]).read_text()
    assert "matuwall" in wallpaper_pick
    assert "--backend-command" in wallpaper_pick
    assert "wallpaper-apply {path}" in wallpaper_pick
    assert "--recursive" in wallpaper_pick
    assert "fuzzel" not in wallpaper_pick and "swaybg" not in wallpaper_pick
    assert "swaybg" not in m["units"]
    managed_source = Path(m["wallpaperManagedSource"])
    expected_names = sorted(["wallpaper-001.jpg", "wallpaper-002.jpg"] + [f"wallpaper-{n:03d}.png" for n in range(3, 19)])
    assert sorted(asset["name"] for asset in m["wallpaperAssets"]) == expected_names
    assert sorted(path.name for path in managed_source.iterdir()) == expected_names
    assert all(path.is_symlink() and path.is_file() for path in managed_source.iterdir())
    assert all(Path(asset["path"]).is_file() for asset in m["wallpaperAssets"])
    greeter_wallpaper = re.search(r'url\("file://(/nix/store/[^"]+)"\)', m["greeter"]["css"])
    assert greeter_wallpaper and Path(greeter_wallpaper.group(1)).is_file()
    assert "background-size: cover" in m["greeter"]["css"]
    activation = m["wallpaperActivation"]
    local_path = str(Path(m["wallpaperRoot"]) / "local")
    assert activation.count(local_path) == 1
    assert not re.search(r"\b(rm|cp|mv|ln|install)\b", activation)
    fixture_root = out / "wallpaper-activation"
    fixture_local = fixture_root / "Pictures" / "Wallpapers" / "local"
    activation = activation.replace(local_path, str(fixture_local))
    activation_script = out / "wallpaper-local-activation.sh"
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

    # Lock/idle: standalone swaylock for ext-session-lock; swayidle only locks
    # before sleep and has no inactivity timers.
    lock = m["swaylock"]
    assert lock["enable"] and lock["pamService"]
    assert lock["settings"]["inside-color"].endswith("e6")
    assert lock["settings"]["text-color"] == palette["brightFg"].removeprefix("#") + "ff"
    idle = m["swayidle"]
    assert idle["enable"]
    assert idle["timeouts"] == []
    assert "session-lock" in idle["events"]["before-sleep"]

    # mangobar: tray, real CPU/memory percents, network, battery, clock.
    # Bluetooth stays a hardware feature; the bar does not poll it.
    bar = m["mangobar"]
    assert bar["height"] == 30 and bar["layer"] == "top"
    assert "buffer-scale" not in bar and "keyboardlayout" not in bar
    assert "custom/bluetooth" not in bar
    assert bar["modules-left"] == ["layout", "workspaces", "hideclients"]
    assert bar["hideclients"]["format"].endswith(" {}")
    assert ord(bar["hideclients"]["format"][0]) == 0xF0209
    assert bar["modules-center"] == ["window"]
    assert bar["modules-right"] == ["tray", "cpu", "memory", "network", "battery", "clock"]
    assert bar["window"]["max-length"] == 300 and "on-click" not in bar["window"]
    assert bar["clock"]["format"] == "{:L%m月%d日 周%a %H:%M}"
    assert bar["network"]["format-wifi"] == "{signal}"
    assert ord(bar["network"]["icon-wifi"]) == 0xF05A9
    assert bar["battery"]["on-click"] == "legion-conservation toggle"
    assert bar["battery"]["hide-on-ac"] is False
    # {usage} is /proc/stat. {load} is the 1-minute load average.
    assert bar["cpu"]["format"] == "CPU {usage}%" and bar["cpu"]["interval"] == 2
    assert "{load}" not in bar["cpu"]["format"]
    assert bar["memory"]["format"] == "MEM {}%" and bar["memory"]["interval"] == 2
    style = m["mangobarStyle"]
    assert 'font-family: "Maple Mono NF CN"' in style
    assert "font-weight: Medium" in style
    assert "text-decoration" not in style and "underline" not in style
    assert "background: none" in style and "border-radius: 0" in style
    assert "#cpu" in style and "#mem" in style and "#hideclients" in style
    assert "#custom-bluetooth" not in style
    assert "#tags.active" in style
    assert palette["blue"] in style
    # Tray DBusMenu popup: One Dark surface/border/radius, item text, hover
    # highlight and the patched disabled-item colour.
    assert "menu {" in style
    assert "border-radius: 12px" in style
    assert "menuitem:disabled" in style
    for key in ("surface", "border", "selection", "brightFg", "muted"):
        assert palette[key] in style, key
    mangobar_patches = {patch["name"]: patch["content"] for patch in m["mangobarPatches"]}
    assert set(mangobar_patches) == {"menuitem-disabled.patch"}
    disabled_patch = mangobar_patches["menuitem-disabled.patch"]
    assert "menuitem_disabled" in disabled_patch
    assert "lr = dis_r;" in disabled_patch

    # fuzzel: the only launcher. Icons stay at the ini default; Alt+Space
    # passes --no-icons. Super+V does not use fuzzel.
    fuzzel = m["fuzzel"]
    assert fuzzel["main"]["font"] == palette["fonts"]["sans"] + ":size=14"
    assert fuzzel["main"]["icon-theme"] == palette["iconTheme"]
    assert "icons-enabled" not in fuzzel["main"]
    clipboard = Path(m["clipboardHistory"]).read_text()
    assert "kitty --class=cliphist-tui" in clipboard
    assert "CT_COPY_MARK" in clipboard
    assert "cliphist-tui" in clipboard
    assert "fuzzel" not in clipboard
    assert "\\0icon" not in clipboard
    assert "-thumbnail" not in clipboard
    assert "paste-key ctrl shift v" in clipboard
    assert "paste-key ctrl v" in clipboard
    assert "wtype" not in clipboard
    assert "cliphist-tui-keep-history.patch" in m["cliphistTuiNix"]
    assert "CT_COPY_MARK" in m["cliphistTuiPatch"]
    assert "-    delete_clip_by_id(id);" in m["cliphistTuiPatch"]
    assert fuzzel["main"]["width"] == 60 and fuzzel["main"]["anchor"] == "center"
    assert fuzzel["main"]["lines"] == 8
    assert fuzzel["main"]["horizontal-pad"] == 20 and fuzzel["main"]["vertical-pad"] == 10
    assert fuzzel["main"]["line-height"] == 22
    assert fuzzel["colors"]["background"] == palette["surface"].removeprefix("#") + "ff"
    assert fuzzel["border"]["width"] == 1

    # mako remains the notification daemon on the Mango target.
    assert not (
        Path(m["makoPackage"]) / "share/dbus-1/services/fr.emersion.mako.service"
    ).exists()
    mako_dbus = m["makoDbusService"]
    assert "Name=org.freedesktop.Notifications" in mako_dbus
    assert "SystemdService=mako.service" in mako_dbus
    mako = m["mako"]
    assert mako["anchor"] == "top-right" and mako["width"] == 360
    assert mako["background-color"] == palette["surface"]
    assert mako["outer-margin"] == "42,28,0,0" and mako["margin"] == "0,0,8,0"
    assert mako["max-visible"] == 3 and mako["border-size"] == 1
    on_notify = mako["on-notify"]
    assert on_notify.startswith("exec ")
    assert "/bin/pw-play" in on_notify
    assert "message-new-instant.oga" in on_notify

    # swayosd: compact popup, libinput backend and palette style.
    logical = 1600 / 1.5
    assert abs(m["swayosd"]["topMargin"] - ((logical - 96 - 26) / logical)) < 1e-6
    swayosd_style = Path(m["swayosd"]["style"]).read_text()
    assert "border-radius: 999px" in swayosd_style
    assert palette["surface"] in swayosd_style
    assert "show_percentage = true" in m["swayosdConfig"]
    backend = m["swayosdBackend"]
    assert backend["wantedBy"] == [ "multi-user.target" ]
    assert backend["execStart"].endswith("/bin/swayosd-libinput-backend")
    assert backend["restart"] == "always"
    assert m["swayosdSystemBusPolicy"]
    assert "org.erikreider.swayosd-libinput-backend" in m["swayosdPolkit"]
    assert "margin: 8px 14px" in swayosd_style
    assert "font-size: 13px" in swayosd_style
    assert "min-height: 4px" in swayosd_style
    assert "duration" not in m["swayosdConfig"]
    assert m["videoGroup"] and m["swayosdUdev"]

    # Session units all bind to the Mango target; fcitx5/xrdb follow the
    # shared graphical-session targets that session-support declares.
    for name, unit in m["units"].items():
        targets = m["sharedTargets"] if name in ("fcitx5-daemon", "xrdb-merge") else ["mango-session.target"]
        assert unit["Unit"]["PartOf"] == targets, name
        assert unit["Unit"]["After"] == targets, name
        assert unit["Install"]["WantedBy"] == targets, name
    for name in ("mangobar", "mako", "swayosd", "sweetbgd", "swayidle", "polkit-gnome-authentication-agent-1", "cliphist", "cliphist-images", "wl-clip-persist"):
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
    polkit_exec = command(m["units"]["polkit-gnome-authentication-agent-1"]["Service"]["ExecStart"])
    assert "/libexec/polkit-gnome-authentication-agent-1" in polkit_exec
    swayosd_exec = command(m["units"]["swayosd"]["Service"]["ExecStart"])
    assert "swayosd-libinput" not in swayosd_exec
    assert "--top-margin" in swayosd_exec
    assert m["units"]["swayosd"]["Unit"]["StartLimitBurst"] == 3
    assert m["units"]["cliphist"]["Service"]["Restart"] == "always"
    assert m["units"]["cliphist-images"]["Service"]["Restart"] == "always"
    assert "--reconnect-tries 0" in command(m["units"]["wl-clip-persist"]["Service"]["ExecStart"])
    assert m["units"]["wl-clip-persist"]["Service"]["Restart"] == "always"
    lock_before_sleep = m["units"]["swayidle"]["Service"]["ExecStart"]
    assert "before-sleep" in command(lock_before_sleep)
    assert "suspend" not in command(lock_before_sleep)

    # Session environment: only the static whitelist reaches the user manager,
    # and no credential-looking name is present.
    env = m["environment"]
    for name in env:
        assert "KEY" not in name and "TOKEN" not in name and "SECRET" not in name, name
    assert "NVIM_CLAUDE_ACP" not in env
    assert "NVIM_CLAUDE_ACP" not in m["shellEnvironment"]
    assert m["environment"]["XCURSOR_THEME"] == palette["cursor"]["name"]
    assert m["environment"]["XCURSOR_SIZE"] == str(palette["cursor"]["size"])

    # Greeter, boot and console contract remains untouched by this feature.
    assert palette["bg"] in m["greeter"]["css"]
    assert "output eDP-1 scale 1.5" in m["greeter"]["sway"]
    session = m["greeter"]["environments"].strip()
    assert " " not in session and len(session) < 128
    assert session in m["greeter"]["sway"]
    login = Path(session).read_text()
    assert "XDG_SESSION_TYPE=wayland" in login
    assert "XDG_CURRENT_DESKTOP=mango:wlroots" in login
    assert "XDG_SESSION_DESKTOP=mango" in login
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
    PY
  ''
