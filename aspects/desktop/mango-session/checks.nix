{
  pkgs,
  home,
  nixos,
  appearance,
  ...
}:
{
  mango-blur-sampling = import ./mango/blur-check.nix {
    inherit pkgs;
    mango = nixos.programs.mango.package;
  };

  # Renders the real patched mangobar package and generated stylesheet in a
  # private headless sway, with two independent StatusNotifierItem/DBusMenu
  # services and injected pointer clicks; checks menu geometry, corner radius
  # and palette pixels for background, border, item text, hover and disabled
  # rows, plus the side submenu.
  mangobar-tray-pixels = import ./mangobar/check.nix {
    inherit pkgs home;
    palette = appearance;
  };

  # Headless test for the overlay package. The session does not use it:
  # fuzzel is the launcher and Super+V is cliphist-tui, so this check wires
  # neither binding.
  mayon-overlay = import ../../../packages/mayon-overlay/tests/check.nix {
    inherit pkgs;
  };

  # Validates Mango, mangobar, fuzzel, mako, swayosd, sweetbgd, swayidle, the
  # clipboard units, the wallpaper link farm and the avatar hand-off.
  interactive-session-config = import ./runtime-check.nix {
    inherit pkgs home;
    host = nixos;
    palette = appearance;
  };
}
