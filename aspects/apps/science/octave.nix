{ pkgs }:
let
  octave = pkgs.octaveFull;
  # Octave 11's GUI is a Qt 5 application, but the session exports
  # QT_QPA_PLATFORMTHEME=qt6ct for every Qt application. Qt 5 cannot load the
  # Qt 6 platform-theme plugin and silently falls back to light Fusion, so ask
  # for qt5ct here instead. The palette itself is seeded by
  # graphical-session-support from the shared One Dark colour file; this only
  # selects the plugin and makes its directory visible, because Octave's own
  # wrapper prefixes QT_PLUGIN_PATH with its Qt 5 dependencies only.
  qt5ctPluginPath = "${pkgs.libsForQt5.qt5ct}/${pkgs.libsForQt5.qtbase.qtPluginPrefix}";
in
pkgs.symlinkJoin {
  name = "${octave.name}-qt5ct";
  paths = [ octave ];
  nativeBuildInputs = [ pkgs.makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/octave \
      --set QT_QPA_PLATFORMTHEME qt5ct \
      --prefix QT_PLUGIN_PATH : ${qt5ctPluginPath}

    # The upstream desktop entry names the inner binary, so starting Octave
    # from fuzzel would bypass the wrapper above and fall back to light Fusion.
    rm -rf $out/share/applications
    mkdir -p $out/share/applications
    substitute ${octave}/share/applications/org.octave.Octave.desktop \
      $out/share/applications/org.octave.Octave.desktop \
      --replace-fail "${octave}/bin/octave" "$out/bin/octave"
  '';
}
