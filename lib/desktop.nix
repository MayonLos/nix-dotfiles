# Cross-scope desktop constants: values that both NixOS modules and Home
# Manager modules must agree on. Pure data -- import by relative path from
# either tree.
{
  cursor = {
    name = "Bibata-Modern-Ice";
    size = 24;
  };

  # The single laptop panel. A wrong name makes screencast capture black with
  # no log (modules/system/desktop/xdg.nix) and keys the bar's backlight
  # control off a stale output.
  primaryOutput = "eDP-1";

  # Must stay a mutable path, not a store copy: programs.nh.flake and the
  # Noctalia plugin tooling read the live repo.
  repoPath = "/home/mayon/nix-dotfiles";

  # GTK (home.pointerCursor/gtk.iconTheme) and the qt6ct/qt5ct conf written by
  # base/qt.nix must name the same icon theme or Qt apps fall back to the
  # default icons.
  iconTheme = "Papirus-Dark";
}
