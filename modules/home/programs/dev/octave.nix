{ pkgs, ... }:
let
  # MATLAB itself is still not a derivation -- its installer requires a
  # MathWorks login, so nothing can fetch it -- but matlab.nix now wraps an
  # imperative install in an FHS environment, so Simulink and the commercial
  # toolboxes are available. Octave stays: it starts in a second, needs no
  # licence server, and covers .m coursework on its own.
  #
  # octaveFull rather than octave: the only difference is the Qt GUI, and Qt is
  # already in this host's closure for other applications. Measured with
  # `nix build --dry-run`: octave adds 458.7 MiB, octaveFull 535.4 MiB. The
  # 77 MiB buys the variable browser and the debugger, which is the part a
  # terminal cannot replace.
  env = pkgs.octaveFull.withPackages (
    # The toolbox equivalents are compiled against this exact octave, so they
    # are built locally instead of substituted -- a few minutes on the first
    # rebuild only. All seven add 134 MiB.
    #
    # Installing a package does not put it on the path: octave needs an
    # explicit `pkg load signal` per session, unlike MATLAB's path mechanism.
    # ~/.octaverc is the place to automate that, and it is deliberately left
    # unmanaged -- it is per-project taste, not configuration.
    ps: with ps; [
      signal # Signal Processing Toolbox
      control # Control System Toolbox
      image # Image Processing Toolbox
      statistics # Statistics and Machine Learning Toolbox
      optim # Optimization Toolbox
      io # the xlsx/csv readers MATLAB has built in
      symbolic # Symbolic Math Toolbox -- syms/solve/diff/int, via sympy
    ]
  );
in
{
  home.packages = [
    # Octave 11's GUI is Qt5, and mango exports QT_QPA_PLATFORMTHEME=qt6ct,
    # which Qt5 cannot use -- it looks for a platformtheme plugin by that name,
    # finds none, and draws the whole window in light Fusion against a dark
    # desktop. Asking for qt5ct here is the narrowest fix: it themes the one
    # Qt5 application on this host without touching the global variable that
    # every Qt6 application depends on. base/qt.nix seeds the qt5ct config,
    # pointed at the palette noctalia already renders.
    (pkgs.symlinkJoin {
      name = "octave-qt5ct-${pkgs.octaveFull.version}";
      paths = [ env ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = ''
        # Asking for the theme is not enough: Qt only loads a platformtheme
        # plugin it can find, and octave's own wrapper prefixes QT_PLUGIN_PATH
        # with its Qt5 dependencies only. qt5ct sitting in the user profile is
        # invisible to it, so name the plugin directory explicitly. Octave uses
        # --prefix rather than --set for this variable, which is why the two
        # wrappers compose instead of one clobbering the other.
        #
        # Verified with QT_DEBUG_PLUGINS=1 against the built binary: the line
        # to look for is `loaded library ".../platformthemes/libqt5ct.so"`.
        # That trace also shows the plugin registering *both* keys --
        # `Got keys from plugin meta data ("qt5ct", "qt6ct")` -- so the global
        # qt6ct value would have worked too. The variable name was never the
        # problem; the plugin being unreachable was.
        wrapProgram $out/bin/octave \
          --set QT_QPA_PLATFORMTHEME qt5ct \
          --prefix QT_PLUGIN_PATH : ${pkgs.libsForQt5.qt5ct}/lib/qt-${pkgs.libsForQt5.qtbase.version}/plugins

        # withPackages baked the *inner* env's path into the desktop entry's
        # Exec line. Left alone, launching Octave from the app launcher would
        # run that binary directly and never reach the wrapper above -- the GUI
        # would still be light, and only a terminal `octave` would be themed.
        rm -rf $out/share/applications
        mkdir -p $out/share/applications
        substitute ${env}/share/applications/org.octave.Octave.desktop \
          $out/share/applications/org.octave.Octave.desktop \
          --replace-fail "${env}/bin/octave" "$out/bin/octave"
      '';
    })
  ];
}
