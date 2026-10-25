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
pkgs.runCommand "application-portals-theme-check"
  {
    nativeBuildInputs = [ pkgs.python3 ];
  }
  ''
    mkdir -p "$out"
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
