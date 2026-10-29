{ pkgs }:

let
  finderCss = pkgs.runCommand "thunar-finder-css" { } ''
    mkdir -p "$out/share/thunar"
    cp ${./resources/finder.css} "$out/share/thunar/finder.css"
  '';
  thunar = pkgs.thunar-unwrapped.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./resources/finder-shell.patch ];
    postPatch = (old.postPatch or "") + ''
      substituteInPlace thunar/thunar-application.c \
        --replace-fail '@finderCss@' '${finderCss}/share/thunar/finder.css'
      # Fail closed on upstream changes to the patched grouping and DnD boundary.
      grep -F 'THUNAR_SHORTCUT_GROUP_FAVORITES_HEADER' thunar/thunar-shortcuts-model.c
      grep -F 'thunar_shortcuts_view_header_style' thunar/thunar-shortcuts-view.c
      grep -F 'GTK_STYLE_PROVIDER_PRIORITY_USER + 1' thunar/thunar-application.c
    '';
    passthru = (old.passthru or { }) // {
      inherit finderCss;
    };
  });
  archivePlugin = pkgs.thunar-archive-plugin.overrideAttrs (oldAttrs: {
    postInstall = (oldAttrs.postInstall or "") + ''
      # The locked Thunar Archive Plugin ships the upstream TAPs. Keep this
      # assertion so the custom action cannot silently disappear on upgrades.
      tap_dir="$out/libexec/thunar-archive-plugin"
      if [ -e "$tap_dir/gnome-file-roller.tap" ] && [ ! -e "$tap_dir/file-roller.tap" ]; then
        ln -s gnome-file-roller.tap "$tap_dir/file-roller.tap"
      fi
      if [ ! -e "$tap_dir/file-roller.tap" ] && [ ! -e "$tap_dir/org.gnome.FileRoller.tap" ]; then
        echo "thunar-archive-plugin did not install a File Roller TAP handler" >&2
        exit 1
      fi
      tap_file="$tap_dir/file-roller.tap"
      if [ ! -e "$tap_file" ]; then
        tap_file="$tap_dir/org.gnome.FileRoller.tap"
      fi
      substituteInPlace "$tap_file" \
        --replace-fail 'file-roller' '${pkgs.file-roller}/bin/file-roller'
    '';
  });
  plugins = [
    archivePlugin
    pkgs.thunar-volman
  ];
  thunarWithPlugins =
    (pkgs.thunar.override {
      thunar-unwrapped = thunar;
      thunarPlugins = plugins;
    }).overrideAttrs
      (old: {
        # Upstream's wallpaper action only supports XFCE/GNOME and otherwise does
        # nothing. Keep our session-aware UCA as the only wallpaper action. This
        # removes symlinks from this wrapper, never files in the original package.
        buildCommand = old.buildCommand + ''
                      test -L "$out/lib/thunarx-3/thunar-wallpaper-plugin.so"
                      rm "$out/lib/thunarx-3/thunar-wallpaper-plugin.so"
                      if [ -L "$out/lib/thunarx-3/thunar-wallpaper-plugin.la" ]; then
                        rm "$out/lib/thunarx-3/thunar-wallpaper-plugin.la"
                      fi

                      # Publish the canonical bus filename once from the host package.
                      service_dir="$out/share/dbus-1/services"
                      mv "$service_dir/org.xfce.Thunar.FileManager1.service" \
                        "$service_dir/org.freedesktop.FileManager1.service"

                      # Keep Thunar's UI and UCA action labels in Chinese without changing
                      # the session locale globally. The UCA parser matches xml:lang with
                      # LC_MESSAGES (not LANGUAGE), so supply a Chinese message locale
                      # only when neither selector was explicitly set. Respect C/English.
                      for app in thunar thunar-settings; do
                        substituteInPlace "$out/bin/$app" \
                          --replace-fail 'export THUNARX_DIRS=' \
                            'if [ "''${LANGUAGE+x}" != x ]; then
            export LANGUAGE="zh_CN:en_US"
            if [ "''${LC_MESSAGES+x}" != x ] && [ "''${LC_ALL+x}" != x ]; then export LC_MESSAGES="zh_CN.UTF-8"; fi
          fi
                export THUNARX_DIRS='
                      done
        '';
      });
in
{
  inherit plugins thunarWithPlugins finderCss;
}
