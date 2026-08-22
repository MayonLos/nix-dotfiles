{ pkgs, config, ... }:
{
  # Qt apps (mark-shot, virt-manager's dialogs, ...) used to ignore the theme:
  # file dialogs came up in flat light-grey default Fusion.
  #
  # The setup was only half done. niri's environment sets
  # QT_QPA_PLATFORMTHEME=qt6ct and noctalia's qt template renders the palette to
  # ~/.config/qt6ct/colors/noctalia.conf, but qt6ct's own qt6ct.conf was never
  # written -- without it qt6ct does not know which palette to use and falls
  # back to the default light one.
  #
  # That file is mutable (qt6ct's own GUI writes it too), so seed it from an
  # activation script instead of a home.file symlink: created only when missing,
  # so whatever you later tweak inside qt6ct is never overwritten.
  home.activation.seedQt6ctConfig =
    let
      colorScheme = "${config.home.homeDirectory}/.config/qt6ct/colors/noctalia.conf";
      conf = pkgs.writeText "qt6ct.conf" ''
        [Appearance]
        color_scheme_path=${colorScheme}
        custom_palette=true
        icon_theme=Papirus-Dark
        standard_dialogs=default
        style=Fusion
      '';
    in
    config.lib.dag.entryAfter [ "writeBoundary" ] ''
      target="${config.home.homeDirectory}/.config/qt6ct/qt6ct.conf"
      if [ ! -e "$target" ]; then
        run mkdir -p "$(dirname "$target")"
        run ${pkgs.coreutils}/bin/install -m 0644 ${conf} "$target"
      fi
    '';
}
