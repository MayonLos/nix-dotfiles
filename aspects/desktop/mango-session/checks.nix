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

  # Validates Mango, mangobar, fuzzel, mako, swayosd, swaybg, swayidle, the
  # clipboard units, the wallpaper link farm and the avatar hand-off.
  interactive-session-config = import ./runtime-check.nix {
    inherit pkgs home;
    host = nixos;
    palette = appearance;
  };
}
