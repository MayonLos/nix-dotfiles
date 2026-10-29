{
  pkgs,
  home,
  nixos,
  appearance,
  ...
}:
let
  gtk2rc = pkgs.writeText "gtk2-one-dark-gtkrc" home.home.file.${home.gtk.gtk2.configLocation}.text;
  kdeglobals = home.xdg.configFile.kdeglobals.source;
  scheme = home.xdg.dataFile."color-schemes/NixDotfilesOneDark.colors".source;
  rgb =
    color:
    pkgs.lib.concatMapStringsSep ","
      (offset: toString (pkgs.lib.fromHexString (builtins.substring offset 2 color)))
      [
        1
        3
        5
      ];
in
assert home.gtk.gtk2.theme.name == "Adwaita-dark";
assert home.home.sessionVariables.GTK_PATH == "${home.gtk.gtk2.theme.package}/lib/gtk-2.0";
assert home.systemd.user.sessionVariables.GTK_PATH == home.home.sessionVariables.GTK_PATH;
assert
  home.home.sessionVariables.QT_PLUGIN_PATH
  == "${pkgs.qt6Packages.qt6ct}/${pkgs.qt6Packages.qtbase.qtPluginPrefix}";
assert
  home.systemd.user.sessionVariables.QT_PLUGIN_PATH == home.home.sessionVariables.QT_PLUGIN_PATH;
assert home.home.sessionVariables.GTK_USE_PORTAL == "1";
assert home.systemd.user.sessionVariables.GTK_USE_PORTAL == "1";
assert home.home.pointerCursor.name == "phinger-cursors-light";
assert home.home.pointerCursor.package == pkgs.phinger-cursors;
assert home.home.sessionVariables.XCURSOR_THEME == home.home.pointerCursor.name;
assert home.systemd.user.sessionVariables.XCURSOR_SIZE == toString home.home.pointerCursor.size;
assert
  pkgs.lib.toList nixos.xdg.portal.config.mango."org.freedesktop.impl.portal.FileChooser"
  == [ "gtk" ];
assert
  pkgs.lib.toList nixos.xdg.portal.config.dwm."org.freedesktop.impl.portal.FileChooser" == [ "gtk" ];
assert
  pkgs.lib.toList nixos.xdg.portal.config.mango."org.freedesktop.impl.portal.Settings" == [ "gtk" ];
assert
  pkgs.lib.toList nixos.xdg.portal.config.dwm."org.freedesktop.impl.portal.Settings" == [ "gtk" ];
assert !(builtins.elem pkgs.xdg-desktop-portal-gnome nixos.xdg.portal.extraPortals);
pkgs.runCommand "application-portals-theme-check"
  {
    nativeBuildInputs = [
      pkgs.python3
      pkgs.dbus
    ];
  }
  ''
    mkdir -p "$out"
    python3 - ${nixos.environment.etc."dbus-1".source} ${nixos.system.path} <<'PYDBUS'
    import configparser, pathlib, sys, xml.etree.ElementTree as ET
    config, profile = map(pathlib.Path, sys.argv[1:])
    def names(directory):
        result = []
        for path in directory.glob("*.service"):
            parser = configparser.ConfigParser(interpolation=None, strict=False)
            parser.read(path)
            result.append(parser["D-BUS Service"]["Name"])
        assert len(result) == len(set(result)), result
        return set(result)
    system_names = names(profile / "share/dbus-1/services")
    for bus in ("session", "system"):
        tree = ET.parse(config / f"{bus}.conf")
        directories = tree.findall("servicedir")
        assert len(directories) == 1
        extra_names = names(pathlib.Path(directories[0].text))
        if bus == "session":
            assert tree.find("standard_session_servicedirs") is not None
            assert not system_names & extra_names
        else:
            assert "org.freedesktop.nm_dispatcher" in extra_names
    PYDBUS
    # Parse the production session config on a private bus. Its standard dirs
    # contain the generated system profile and an isolated user-service fixture.
    # Do not couple this portal check to unrelated proprietary HM packages.
    export HOME="$TMPDIR/private-home"
    export XDG_DATA_HOME="$HOME/.local/share"
    export XDG_DATA_DIRS=${nixos.system.path}/share
    mkdir -p "$XDG_DATA_HOME/dbus-1/services"
    cat > "$XDG_DATA_HOME/dbus-1/services/org.example.NixDotfilesTest.service" <<EOF
    [D-BUS Service]
    Name=org.example.NixDotfilesTest
    Exec=${pkgs.coreutils}/bin/false
    EOF
    dbus-run-session --config-file=${nixos.environment.etc."dbus-1".source}/session.conf -- \
      python3 - ${nixos.environment.etc."dbus-1".source}/service-providers.json <<'PYACTIVATION'
    import json, subprocess, sys
    expected = json.load(open(sys.argv[1]))["session"]
    names = subprocess.check_output([
        "dbus-send", "--session", "--print-reply", "--dest=org.freedesktop.DBus",
        "/org/freedesktop/DBus", "org.freedesktop.DBus.ListActivatableNames"
    ], text=True)
    required = set(expected["providers"]) | set(expected["standard_profile_names"])
    required.add("org.example.NixDotfilesTest")
    for name in required:
        assert f'string "{name}"' in names, (name, names)
    PYACTIVATION
    test -f ${home.home.sessionVariables.QT_PLUGIN_PATH}/platformthemes/libqt6ct.so
    test -f ${home.gtk.gtk2.theme.package}/share/themes/Adwaita-dark/gtk-2.0/gtkrc
    grep -F 'gtk-theme-name = "Adwaita-dark"' ${gtk2rc}
    grep -F 'bg[NORMAL] = "${appearance.bg}"' ${gtk2rc}
    cp ${gtk2rc} "$out/gtkrc-2.0"
    cp ${kdeglobals} "$out/kdeglobals"
    cp ${scheme} "$out/NixDotfilesOneDark.colors"
    test -f ${home.home.pointerCursor.package}/share/icons/${home.home.pointerCursor.name}/cursors/left_ptr
    python3 - "$out" <<'PY'
    import configparser, pathlib, sys
    root = pathlib.Path(sys.argv[1])
    for name in ("kdeglobals", "NixDotfilesOneDark.colors"):
        cfg = configparser.ConfigParser()
        cfg.read(root / name)
        for group, bg in {"Window": "${rgb appearance.bg}", "View": "${rgb appearance.deep}", "Button": "${rgb appearance.surface}", "Selection": "${rgb appearance.selection}"}.items():
            assert cfg[f"Colors:{group}"]["BackgroundNormal"] == bg
            assert cfg[f"Colors:{group}"]["ForegroundNormal"] == "${rgb appearance.brightFg}"
            assert cfg[f"Colors:{group}"]["DecorationFocus"] == "${rgb appearance.blue}"
        assert cfg["General"]["ColorScheme"] == "NixDotfilesOneDark"
        if name == "kdeglobals":
            assert cfg["Icons"]["Theme"] == "${appearance.iconTheme}"
            assert cfg["KDE"]["widgetStyle"] == "Fusion"
            assert cfg["KDE"].getboolean("ShowIconsInMenuItems")
            assert cfg["KDE"].getboolean("ShowIconsOnPushButtons")
    PY
  ''
