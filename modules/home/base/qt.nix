{ pkgs, config, ... }:
{
  # Qt apps (mark-shot, virt-manager's dialogs, ...) used to ignore the theme:
  # file dialogs came up in flat light-grey default Fusion.
  #
  # The setup was only half done. Mango's environment sets
  # QT_QPA_PLATFORMTHEME=qt6ct and noctalia's qt template renders the palette to
  # ~/.config/qt6ct/colors/noctalia.conf, but qt6ct's own qt6ct.conf was never
  # written -- without it qt6ct does not know which palette to use and falls
  # back to the default light one.
  #
  # That file is mutable (qt6ct's own GUI writes it too), so seed it from an
  # activation script instead of a home.file symlink: created only when missing,
  # so whatever you later tweak inside qt6ct is never overwritten.
  #
  # qt5ct is the same story for the one Qt5 application on this host. Octave's
  # GUI is Qt5 (qtbase-5.15.19 + qscintilla-qt5), and QT_QPA_PLATFORMTHEME=qt6ct
  # means nothing to Qt5 -- it looks for a platformtheme plugin named qt6ct,
  # finds none, and renders in light Fusion. octave.nix wraps its binaries to
  # ask for qt5ct instead; this seeds what qt5ct then reads.
  #
  # Both point at the *same* palette file, the one noctalia renders into the
  # qt6ct directory. noctalia has no qt5ct template and does not need one: the
  # format is version-independent, as the header of the generated file says --
  # "Qt6 didn't add/delete/change any of the color functions". Sharing the file
  # rather than copying it is what keeps Octave in step when the theme changes
  # at runtime.
  home.activation =
    let
      colorScheme = "${config.home.homeDirectory}/.config/qt6ct/colors/noctalia.conf";
      mkConf =
        name:
        pkgs.writeText "${name}.conf" ''
          [Appearance]
          color_scheme_path=${colorScheme}
          custom_palette=true
          icon_theme=Papirus-Dark
          standard_dialogs=default
          style=Fusion
        '';
      seed =
        name:
        config.lib.dag.entryAfter [ "writeBoundary" ] ''
          target="${config.home.homeDirectory}/.config/${name}/${name}.conf"
          if [ ! -e "$target" ]; then
            run mkdir -p "$(dirname "$target")"
            run ${pkgs.coreutils}/bin/install -m 0644 ${mkConf name} "$target"
          fi
        '';
    in
    {
      seedQt6ctConfig = seed "qt6ct";
      seedQt5ctConfig = seed "qt5ct";
    };
}
