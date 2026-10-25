{ pkgs }:

let
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
  thunarWithPlugins = (pkgs.thunar.override { thunarPlugins = plugins; }).overrideAttrs (old: {
    # Upstream's wallpaper action only supports XFCE/GNOME and otherwise does
    # nothing. Keep our session-aware UCA as the only wallpaper action. This
    # removes symlinks from this wrapper, never files in the original package.
    buildCommand = old.buildCommand + ''
      test -L "$out/lib/thunarx-3/thunar-wallpaper-plugin.so"
      rm "$out/lib/thunarx-3/thunar-wallpaper-plugin.so"
      if [ -L "$out/lib/thunarx-3/thunar-wallpaper-plugin.la" ]; then
        rm "$out/lib/thunarx-3/thunar-wallpaper-plugin.la"
      fi
    '';
  });
in
{
  inherit plugins thunarWithPlugins;
}
